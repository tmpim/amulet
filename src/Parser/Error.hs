{-# LANGUAGE OverloadedStrings, MultiParamTypeClasses #-}

-- | Represents and handles errors within the parsing process
module Parser.Error
  ( ParseError(..)
  , Terminator(..)
  ) where

import Data.Position
import Data.Spanned
import Data.Span
import Data.Char

import Text.Pretty.Semantic (Pretty(..), Style, verbatim)
import Text.Pretty.Note
import Text.Pretty
import Parser.Token

import Syntax.Pretty

-- | How this token or construct was terminated
data Terminator
  = Newline
  | Eof
  deriving (Show, Eq)

-- | An error in the parsing process
--
-- It's worth noting that not all errors are irrecoverable, though all
-- suggest some form of incorrect code. One should use 'diagnosticKind'
-- to determine how serious an error is.
data ParseError
  -- | Represents an error with an arbitrary message. This is used by
  -- 'fail'
  = Failure SourcePos String

  -- | An unexpected character in the input text
  | UnexpectedCharacter SourcePos Char
  -- | The end of the file was unexpectedly reached
  | UnexpectedEnd SourcePos
  -- | A string was not correctly terminated (due to a new line or the
  -- end of a file)
  | UnclosedString SourcePos SourcePos Terminator
  -- | A comment was not correctly terminated (due to the end of the
  -- file).
  | UnclosedComment SourcePos SourcePos

  -- | An unexpected token appeared in the lexer stream
  | UnexpectedToken Token [String]

  -- | A malformed class declaration
  | MalformedClass Span (Type Parsed)

  -- | An invalid escape code
  | InvalidEscapeCode Span

  -- | __Warning:__ An @in@ was not aligned with its
  -- corresponding @let@
  | UnalignedIn Span Span
  -- | __Warning:__ A context was started at a lower indent than
  -- was expected.
  | UnindentContext Span Span
  deriving (Show)

instance Pretty ParseError where
  pretty (Failure _ s) = string s

  pretty (UnexpectedCharacter _ c) | isPrint c = "Unexpected character '" <> string [c] <> "'"
                                   | otherwise = "Unexpected character" <+> shown c
  pretty (UnexpectedEnd _) = string "Unexpected end of input"
  pretty (UnclosedString _ p Eof) = "Unexpected end of input, expecting to close string started at" <+> prettyPos p
  pretty (UnclosedString _ p Newline) = "Unexpected new line, expecting to close string started at" <+> prettyPos p
  pretty (UnclosedComment _ p) = "Unexpected end of input, expecting to close comment started at" <+> prettyPos p

  pretty (UnexpectedToken (Token s _ _) []) = "Unexpected" <+> string (friendlyName s)
  pretty (UnexpectedToken (Token s _ _) [x]) = "Unexpected" <+> string (friendlyName s) <> ", expected" <+> string x
  pretty (UnexpectedToken (Token s _ _) xs) = "Unexpected" <+> string (friendlyName s) <> ", expected one of" <+> hsep (punctuate comma (map string xs))

  pretty (MalformedClass _ ty) = "Malformed class name" <+> verbatim (pretty ty)

  pretty (InvalidEscapeCode _) = "Unknown escape code."

  pretty (UnalignedIn _ p) = "The in is misaligned with the corresponding 'let'" <+> parens ("located at" <+> prettyPos (spanStart p))
  pretty (UnindentContext _ p) = "Possible incorrect indentation" </> "This token is outside the context started at" <+> prettyPos (spanStart p)

instance Spanned ParseError where
  annotation (Failure p _) = mkSpan1 p

  annotation (UnexpectedCharacter p _) = mkSpan1 p
  annotation (UnexpectedEnd p) = mkSpan1 p
  annotation (UnclosedString p _ _) = mkSpan1 p
  annotation (UnclosedComment p _) = mkSpan1 p

  annotation (UnexpectedToken t _) = annotation t

  annotation (MalformedClass p _) = p

  annotation (InvalidEscapeCode p) = p

  annotation (UnalignedIn p _) = p
  annotation (UnindentContext p _) = p

prettyPos :: SourcePos -> Doc a
prettyPos p = shown (spLine p) <> colon <> shown (spCol p)

instance Note ParseError Style where
  diagnosticKind UnalignedIn{} = WarningMessage
  diagnosticKind UnindentContext{} = WarningMessage
  diagnosticKind _ = ErrorMessage

  formatNote f (UnalignedIn p i)
    = indent 2 "This `in` is misaligned with the corresponding `let`"
      <##> f [p, i]
  formatNote f (UnclosedString p s Eof)
    = indent 2 "Unexpected end of input, expecting `\"` to close string"
      <##> f [mkSpan1 s, mkSpan1 p]
  formatNote f (UnclosedString p s Newline)
    = indent 2 "Unexpected new line, expecting `\"` to close string"
      <##> f [mkSpan1 s, mkSpan1 p]
  formatNote f (UnclosedComment p s)
    = indent 2 "Unexpected end of input, expecting to close comment"
      <##> f [mkSpan1 s, mkSpan1 p]
  formatNote f x
    = indent 2 (Right <$> pretty x)
      <##> f [annotation x]
