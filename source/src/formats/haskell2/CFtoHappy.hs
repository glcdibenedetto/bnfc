{-
    BNF Converter: Happy Generator
    Copyright (C) 2004  Author:  Markus Forberg, Aarne Ranta

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

module CFtoHappy 
       (
       cf2HappyS -- cf2HappyS :: CF -> CFCat -> String
       )
        where

import CF
--import Lexer
import Data.List (intersperse, sort)
import Data.Char
import Options (HappyMode(..))
-- Type declarations

type Rules       = [(NonTerminal,[(Pattern,Action)])]
type NonTerminal = String
type Pattern     = String
type Action      = String
type MetaVar     = String

-- default naming

moduleName  = "HappyParser"
tokenName   = "Token"

-- Happy mode



cf2HappyS :: String -> String -> String -> String -> HappyMode -> Bool -> CF -> String
---- cf2HappyS :: String -> CF -> String
cf2HappyS = cf2Happy

-- The main function, that given a CF and a CFCat to parse according to, 
-- generates a happy module. 
cf2Happy name absName lexName errName mode byteStrings cf 
 = unlines 
    [header name absName lexName errName mode byteStrings,
     declarations mode (allEntryPoints cf),
     tokens (cfTokens cf),
     specialToks cf,
     delimiter,
     specialRules byteStrings cf,
     prRules (rulesForHappy cf),
     finalize byteStrings cf]

-- construct the header.
header :: String -> String -> String -> String -> HappyMode -> Bool -> String
header modName absName lexName errName mode byteStrings = unlines 
         ["-- This Happy file was machine-generated by the BNF converter",
	  "{",
	  "{-# OPTIONS_GHC -fno-warn-incomplete-patterns -fno-warn-overlapping-patterns #-}",
          case mode of 
	    Standard -> "module " ++ modName ++ " where" 
	    GLR      -> "-- module name filled in by Happy",
          "import " ++ absName,
          "import " ++ lexName,
          "import " ++ errName,
          if byteStrings then "import qualified Data.ByteString.Char8 as BS" else "",
          "}"
         ]

{- ----
cf2Happy :: String -> CF -> String
cf2Happy name cf 
 = unlines 
    [header name,
     declarations (allEntryPoints cf),
     tokens (cfTokens cf),
     specialToks cf,
     delimiter,
     specialRules cf,
     prRules (rulesForHappy cf),
     finalize cf]

-- construct the header.
header :: String -> String
header name = unlines 
         ["-- This Happy file was machine-generated by the BNF converter",
	  "{",
          "module Par" ++ name ++ " where", 
          "import Abs"++name,
          "import Lex"++name,
          "import ErrM",
          "}"
         ]
-}

-- The declarations of a happy file.
declarations :: HappyMode -> [NonTerminal] -> String
declarations mode ns = unlines 
                 [generateP ns,
          	  case mode of 
                    Standard -> "-- no lexer declaration"
                    GLR      -> "%lexer { myLexer } { Err _ }",
                  "%monad { Err } { thenM } { returnM }",
                  "%tokentype { " ++ tokenName ++ " }"]
   where generateP []     = []
	 generateP (n:ns) = concat ["%name p",n'," ",n',"\n",generateP ns]
                               where n' = identCat n

-- The useless delimiter symbol.
delimiter :: String
delimiter = "\n%%\n"

-- Generate the list of tokens and their identifiers.
tokens :: [(String,Int)] -> String
tokens toks = "%token \n" ++ prTokens toks
 where prTokens []         = []
       prTokens ((t,k):tk) = " " ++ (convert t) ++ 
                             " { " ++ oneTok t k ++ " }\n" ++
                             prTokens tk
       oneTok t k = "PT _ (TS _ " ++ show k ++ ")"

-- Happy doesn't allow characters such as ��� to occur in the happy file. This
-- is however not a restriction, just a naming paradigm in the happy source file.
convert :: String -> String
convert "\\" = concat ['\'':"\\\\","\'"]
convert xs   = concat ['\'':(escape xs),"\'"]
  where escape [] = []
	escape ('\'':xs) = '\\':'\'':escape xs
	escape (x:xs) = x:escape xs

rulesForHappy :: CF -> Rules
rulesForHappy cf = map mkOne $ ruleGroups cf where
  mkOne (cat,rules) = constructRule cf rules cat

-- For every non-terminal, we construct a set of rules. A rule is a sequence of
-- terminals and non-terminals, and an action to be performed
-- As an optimization, a pair of list rules [C] ::= "" | C k [C]
-- is left-recursivized into [C] ::= "" | [C] C k.
-- This could be generalized to cover other forms of list rules.
constructRule :: CF -> [Rule] -> NonTerminal -> (NonTerminal,[(Pattern,Action)])
constructRule cf rules nt = (nt,[(p,generateAction nt (revF b r) m) | 
     r0 <- rules,
     let (b,r) = if isConsFun (funRule r0) && elem (valCat r0) revs 
                   then (True,revSepListRule r0) 
                 else (False,r0),
     let (p,m) = generatePatterns cf r])
 where
   revF b r = if b then ("flip " ++ funRule r) else (underscore $ funRule r)
   revs = reversibleCats cf
   underscore f | isDefinedRule f   = f ++ "_"
		| otherwise	    = f

-- Generates a string containing the semantic action.
-- An action can for example be: Sum $1 $2, that is, construct an AST
-- with the constructor Sum applied to the two metavariables $1 and $2.
generateAction :: NonTerminal -> Fun -> [MetaVar] -> Action
generateAction nt f ms = unwords $ (if isCoercion f then [] else [f]) ++ ms

-- Generate patterns and a set of metavariables indicating 
-- where in the pattern the non-terminal

generatePatterns :: CF -> Rule -> (Pattern,[MetaVar])
generatePatterns cf r = case rhsRule r of
  []  -> ("{- empty -}",[])
  its -> (unwords (map mkIt its), metas its) 
 where
   mkIt i = case i of
     Left c -> identCat c
     Right s -> convert s
   metas its = [revIf c ('$': show i) | (i,Left c) <- zip [1 ::Int ..] its]
   revIf c m = if (not (isConsFun (funRule r)) && elem c revs) 
                 then ("(reverse " ++ m ++ ")") 
               else m  -- no reversal in the left-recursive Cons rule itself
   revs = reversibleCats cf

-- We have now constructed the patterns and actions, 
-- so the only thing left is to merge them into one string.

prRules :: Rules -> String
prRules = unlines . map prOne
  where
    prOne (nt,[]) = [] -- nt has only internal use
    prOne (nt,((p,a):ls)) =
      unwords [nt', "::", "{", normCat nt, "}\n" ++ 
               nt', ":" , p, "{", a, "}", "\n" ++ pr ls] ++ "\n"
     where 
       nt' = identCat nt
       pr [] = []
       pr ((p,a):ls) = 
         unlines [(concat $ intersperse " " ["  |", p, "{", a , "}"])] ++ pr ls
 
-- Finally, some haskell code.

finalize :: Bool -> CF -> String
finalize byteStrings cf = unlines $
   [
     "{",
     "\nreturnM :: a -> Err a",
     "returnM = return",
     "\nthenM :: Err a -> (a -> Err b) -> Err b",
     "thenM = (>>=)",
     "\nhappyError :: [" ++ tokenName ++ "] -> Err a",
     "happyError ts =", 
     "  Bad $ \"syntax error at \" ++ tokenPos ts ++ ",
     "  case ts of",
     "    [] -> []",
     "    [Err _] -> \" due to lexer error\"", 
     "    _ -> \" before \" ++ unwords (map ("++stringUnpack++" . prToken) (take 4 ts))",
     "",
     "myLexer = tokens"
   ] ++ definedRules cf ++ [ "}" ]
   where
     stringUnpack
       | byteStrings = "BS.unpack"
       | otherwise   = "id"


definedRules cf = [ mkDef f xs e | FunDef f xs e <- pragmasOfCF cf ]
    where
	mkDef f xs e = unwords $ (f ++ "_") : xs' ++ ["=", show e']
	    where
		xs' = map (++"_") xs
		e'  = underscore e
	underscore (App x es)
	    | isLower $ head x	= App (x ++ "_") $ map underscore es
	    | otherwise		= App x $ map underscore es
	underscore e	      = e

-- aarne's modifs 8/1/2002:
-- Markus's modifs 11/02/2002

-- GF literals
specialToks :: CF -> String
specialToks cf = unlines $
		 (map aux (literals cf))
		  ++ ["L_err    { _ }"]
 where aux cat = 
        case cat of
          "Ident"  -> "L_ident  { PT _ (TV $$) }"
          "String" -> "L_quoted { PT _ (TL $$) }"
          "Integer" -> "L_integ  { PT _ (TI $$) }"
          "Double" -> "L_doubl  { PT _ (TD $$) }"
          "Char"   -> "L_charac { PT _ (TC $$) }"
          own      -> "L_" ++ own ++ " { PT _ (T_" ++ own ++ " " ++ posn ++ ") }"
         where
           posn = if isPositionCat cf cat then "_" else "$$"

specialRules :: Bool -> CF -> String
specialRules byteStrings cf = unlines $
                  map aux (literals cf)
 where 
   aux cat = 
     case cat of
         "Ident"   -> "Ident   :: { Ident }   : L_ident  { Ident $1 }" 
	 "String"  -> "String  :: { String }  : L_quoted { "++stringUnpack++" $1 }" 
	 "Integer" -> "Integer :: { Integer } : L_integ  { (read ("++stringUnpack++" $1)) :: Integer }"
	 "Double"  -> "Double  :: { Double }  : L_doubl  { (read ("++stringUnpack++" $1)) :: Double }"
	 "Char"    -> "Char    :: { Char }    : L_charac { (read ("++stringUnpack++" $1)) :: Char }"
	 own       -> own ++ "    :: { " ++ own ++ "} : L_" ++ own ++ " { " ++ own ++ " ("++ posn ++ "$1)}"
		-- PCC: take "own" as type name? (manual says newtype)
      where
         posn = if isPositionCat cf cat then "mkPosToken " else ""

   stringUnpack
     | byteStrings = "BS.unpack"
     | otherwise   = ""

