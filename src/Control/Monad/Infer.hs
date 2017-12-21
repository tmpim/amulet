{-# LANGUAGE FlexibleContexts
  , UndecidableInstances
  , FlexibleInstances
  , GADTs
  , ConstraintKinds
  , StandaloneDeriving
  , MultiParamTypeClasses
  , OverloadedStrings #-}
module Control.Monad.Infer
  ( module M
  , TypeError(..)
  , Constraint(..)
  , Env(..)
  , MonadInfer
  , lookupTy, fresh, freshFrom, runInfer, extend
  , extendKind, extendMany, extendManyK
  , difference, freshTV
  , instantiate
  )
  where

import Control.Monad.Writer.Strict as M hiding ((<>))
import Control.Monad.Reader as M
import Control.Monad.Except as M
import Control.Monad.Gen as M

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Semigroup

import Data.Spanned

import qualified Data.Text as T
import Data.Text (Text)

import Pretty hiding (local, (<>))

import Syntax.Subst
import Syntax

type MonadInfer p m = (MonadError TypeError m, MonadReader Env m, MonadWriter [Constraint p] m, MonadGen Int m)

data Env
  = Env { values :: Map.Map (Var Resolved) (Type Typed)
        , types  :: Set.Set (Var Resolved)
        }
  deriving (Eq, Show, Ord)

instance Monoid Env where
  mappend = (<>)
  mempty = Env mempty mempty

instance Semigroup Env where
  Env a b <> Env a' b' = Env (a <> a') (b <> b')

data Constraint p
  = ConUnify (Expr p) (Type p) (Type p)
deriving instance (Show (Ann p), Show (Var p), Show (Expr p), Show (Type p))
  => Show (Constraint p)

data TypeError where
  NotEqual :: Pretty (Var p) => Type p -> Type p -> TypeError
  Occurs   :: Pretty (Var p) => Var p -> Type p -> TypeError
  NotInScope :: Var Resolved -> TypeError
  EmptyMatch :: (Spanned (Expr p), Pretty (Ann p)) => Expr p -> TypeError
  EmptyBegin :: ( Spanned (Expr p)
                , Pretty (Ann p) )
             => Expr p -> TypeError
  FoundHole :: [Expr Typed] -> TypeError
  ArisingFrom :: (Spanned (f p), Pretty (f p), Pretty (Ann p), Pretty (Var p))
              => TypeError -> f p -> TypeError
  NoOverlap :: Type Typed -> Type Typed -> TypeError
  Note :: Pretty x => TypeError -> x -> TypeError
  Suggestion :: Pretty x => TypeError -> x -> TypeError
  CanNotInstance :: Pretty (Var p)
                 => Type p {- record type -}
                 -> Type p {- instance -}
                 -> TypeError
  Malformed :: Pretty (Var p) => Type p -> TypeError
  IllegalGADT :: Pretty (Var p) => Type p -> TypeError
  RigidBinding :: Pretty (Var p) => Var p -> Type p -> TypeError

lookupTy :: (MonadError TypeError m, MonadReader Env m, MonadGen Int m) => Var Resolved -> m (Type Typed)
lookupTy x = do
  rs <- asks (Map.lookup x . values)
  case rs of
    Just t -> instantiate t `catchError` \e ->
      throwError (Note (Note e (("Arising from instancing of variable " :: Text) <+> verbatim x))
                       (verbatim x <+> (" has principal type " :: Text) <+> verbatim t))
    Nothing -> throwError (NotInScope x)

runInfer :: MonadGen Int m
         => Env
         -> ReaderT Env (WriterT [Constraint p] (ExceptT TypeError m)) a
         -> m (Either TypeError (a, [Constraint p]))
runInfer ct ac = runExceptT (runWriterT (runReaderT ac ct))

fresh :: MonadGen Int m => m (Var Resolved)
fresh = do
  x <- gen
  pure (TgName (alpha !! x) x)

freshFrom :: MonadGen Int m => Text -> m (Var Resolved)
freshFrom t = TgName t <$> gen

extend :: MonadReader Env m => (Var Typed, Type Typed) -> m a -> m a
extend (v, t) = local (\x -> x { values = Map.insert (unTvName v) t (values x) })

extendKind :: MonadReader Env m => Var Typed -> m a -> m a
extendKind v = local (\x -> x { types = Set.insert (unTvName v) (types x) })

extendMany :: MonadReader Env m => [(Var Typed, Type Typed)] -> m a -> m a
extendMany ((v, t):xs) b = extend (v, t) $ extendMany xs b
extendMany [] b = b

extendManyK :: MonadReader Env m => [Var Typed] -> m a -> m a
extendManyK (v:xs) b = extendKind v $ extendManyK xs b
extendManyK [] b = b

alpha :: [Text]
alpha = map T.pack $ [1..] >>= flip replicateM ['a'..'z']

instantiate :: (MonadError TypeError m, MonadGen Int m) => Type Typed -> m (Type Typed)
instantiate (TyForall vs ty) = do
  f <- traverse (const freshTV) vs
  instantiate (apply (Map.fromList (zip vs f)) ty)
instantiate ty = pure ty

difference :: Env -> Env -> Env
difference (Env ma mb) (Env ma' mb') = Env (ma Map.\\ ma') (mb Set.\\ mb')

freshTV :: MonadGen Int m => m (Type Typed)
freshTV = TyVar . TvName <$> fresh

instance (Ord (Var p), Substitutable p (Type p)) => Substitutable p (Constraint p) where
  ftv (ConUnify _ a b) = ftv a `Set.union` ftv b
  apply s (ConUnify e a b) = ConUnify e (apply s a) (apply s b)

instance Pretty (Var p) => Pretty (Constraint p) where
  pprint (ConUnify _ a b) = a
                        <+> opClr (" :=: " :: String) <+> b
