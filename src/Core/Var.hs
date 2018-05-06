{-# LANGUAGE DeriveGeneric, DeriveDataTypeable, TemplateHaskell #-}

module Core.Var where

import qualified Data.Text as T
import Control.Lens
import GHC.Generics
import Pretty
import Data.Data

data CoVar =
  CoVar { _covarId :: {-# UNPACK #-} !Int
        , _covarName :: T.Text
        , _covarInfo :: VarInfo
        }
  deriving (Show, Generic, Data)

instance Eq CoVar where
  (CoVar a _ _) == (CoVar b _ _) = a == b

instance Ord CoVar where
  (CoVar a _ _) `compare` (CoVar b _ _) = a `compare` b

data VarInfo
  = ValueVar
  | DataConVar
  | TypeConVar
  | TypeVar
  | CastVar
  deriving (Eq, Show, Ord, Generic, Data)

makeLenses ''CoVar
makePrisms ''VarInfo


instance Pretty CoVar where
  pretty (CoVar i v _) = text v <> scomment (string "#" <> string (show i))

class (Eq a, Ord a, Pretty a, Show a) => IsVar a where
  toVar :: a -> CoVar
  fromVar :: CoVar -> a

instance IsVar CoVar where
  toVar = id
  fromVar = id
