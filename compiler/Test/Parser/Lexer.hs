module Test.Parser.Lexer (tests) where

import Test.Tasty
import Test.Util

import qualified Data.ByteString.Builder as B
import qualified Data.Text.Encoding as T
import qualified Data.Text as T
import Data.Position
import Data.Spanned

import Parser.Wrapper (ParseResult(..), Token(..), runLexer)
import Parser.Lexer

import Pretty

result :: String -> T.Text -> String
result file contents = 
  case runLexer file (B.toLazyByteString $ T.encodeUtf8Builder contents) lexerContextScan of
    PFailed es -> show $ vsep $ map (\e -> pretty (annotation e) <> colon <+> pretty e) es
    POK _ toks -> tail $ writeToks 0 True toks

  where writeToks _ _ [] = "\n"
        writeToks l f t@(Token tc p:ts)
          | spLine p > l = '\n' : writeToks (l + 1) True t
          | f
          = replicate (spCol p - 1) ' ' ++ show tc ++ writeToks l False ts
          | otherwise
          = " " ++ show tc ++ writeToks l False ts

tests :: TestTree
tests = testGroup "Test.Parse.Lexer" (map (goldenFile result "tests/lexer/") files)

files :: [String]
files =
  [ "fail_unterminated_comment.ml"
  , "fail_unterminated_string.ml"
  , "pass_context_top.ml"
  , "pass_tokens.ml"
  ]
