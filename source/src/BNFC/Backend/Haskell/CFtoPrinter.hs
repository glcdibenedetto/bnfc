{-
    BNF Converter: Pretty-printer generator
    Copyright (C) 2004  Author:  Aarne Ranta

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

module BNFC.Backend.Haskell.CFtoPrinter (cf2Printer) where

import BNFC.CF
import BNFC.Utils
import BNFC.Backend.Haskell.CFtoTemplate
import Data.List (intersperse)
import Data.Char(toLower)

-- derive pretty-printer from a BNF grammar. AR 15/2/2002
cf2Printer :: Bool -> String -> String -> CF -> String
cf2Printer byteStrings name absMod cf = unlines [
  prologue byteStrings name absMod,
  integerRule cf,
  doubleRule cf,
  if hasIdent cf then identRule byteStrings cf else "",
  unlines [ownPrintRule byteStrings cf own | (own,_) <- tokenPragmas cf],
  rules cf
  ]


prologue :: Bool -> String -> String -> String
prologue byteStrings name absMod = unlines [
  "{-# OPTIONS_GHC -fno-warn-incomplete-patterns #-}",
  "module " ++ name +++ "where\n",
  "-- pretty-printer generated by the BNF converter\n",
  "import " ++ absMod,
  "import Data.Char",
  (if byteStrings then "import qualified Data.ByteString.Char8 as BS" else ""),
  "",
  "-- the top-level printing method",
  "printTree :: Print a => a -> String",
  "printTree = render . prt 0",
  "",
  "type Doc = [ShowS] -> [ShowS]",
  "",
  "doc :: ShowS -> Doc",
  "doc = (:)",
  "",
  "render :: Doc -> String",
  "render d = rend 0 (map ($ \"\") $ d []) \"\" where",
  "  rend i ss = case ss of",
  "    \"[\"      :ts -> showChar '[' . rend i ts",
  "    \"(\"      :ts -> showChar '(' . rend i ts",
  "    \"{\"      :ts -> showChar '{' . new (i+1) . rend (i+1) ts",
  "    \"}\" : \";\":ts -> new (i-1) . space \"}\" . showChar ';' . new (i-1) . rend (i-1) ts",
  "    \"}\"      :ts -> new (i-1) . showChar '}' . new (i-1) . rend (i-1) ts",
  "    \";\"      :ts -> showChar ';' . new i . rend i ts",
  "    t  : \",\" :ts -> showString t . space \",\" . rend i ts",
  "    t  : \")\" :ts -> showString t . showChar ')' . rend i ts",
  "    t  : \"]\" :ts -> showString t . showChar ']' . rend i ts",
  "    t        :ts -> space t . rend i ts",
  "    _            -> id",
  "  new i   = showChar '\\n' . replicateS (2*i) (showChar ' ') . dropWhile isSpace",
  "  space t = showString t . (\\s -> if null s then \"\" else (' ':s))",
  "",
  "parenth :: Doc -> Doc",
  "parenth ss = doc (showChar '(') . ss . doc (showChar ')')",
  "",
  "concatS :: [ShowS] -> ShowS",
  "concatS = foldr (.) id",
  "",
  "concatD :: [Doc] -> Doc",
  "concatD = foldr (.) id",
  "",
  "replicateS :: Int -> ShowS -> ShowS",
  "replicateS n f = concatS (replicate n f)",
  "",
  "-- the printer class does the job",
  "class Print a where",
  "  prt :: Int -> a -> Doc",
  "  prtList :: [a] -> Doc",
  "  prtList = concatD . map (prt 0)",
  "",
  "instance Print a => Print [a] where",
  "  prt _ = prtList",
  "",
  "instance Print Char where",
  "  prt _ s = doc (showChar '\\'' . mkEsc '\\'' s . showChar '\\'')",
  "  prtList s = doc (showChar '\"' . concatS (map (mkEsc '\"') s) . showChar '\"')",
  "",
  "mkEsc :: Char -> Char -> ShowS",
  "mkEsc q s = case s of",
  "  _ | s == q -> showChar '\\\\' . showChar s",
  "  '\\\\'-> showString \"\\\\\\\\\"",
  "  '\\n' -> showString \"\\\\n\"",
  "  '\\t' -> showString \"\\\\t\"",
  "  _ -> showChar s",
  "",
  "prPrec :: Int -> Int -> Doc -> Doc",
  "prPrec i j = if j<i then parenth else id",
  ""
  ]

integerRule cf = showsPrintRule cf "Integer"
doubleRule cf = showsPrintRule cf "Double"

showsPrintRule cf t = unlines $ [
  "instance Print " ++ t ++ " where",
  "  prt _ x = doc (shows x)",
  ifList cf t
  ]

identRule byteStrings cf = ownPrintRule byteStrings cf "Ident"

ownPrintRule byteStrings cf own = unlines $ [
  "instance Print " ++ own ++ " where",
  "  prt _ (" ++ own ++ posn ++ ") = doc (showString ("++stringUnpack++" i))",
  ifList cf own
  ]
 where
   posn = if isPositionCat cf own then " (_,i)" else " i"

   stringUnpack | byteStrings = "BS.unpack"
                | otherwise   = ""

-- copy and paste from BNFC.Backend.Haskell.CFtoTemplate

rules :: CF -> String
rules cf = unlines $
  map (\(s,xs) -> case_fun s (map toArgs xs) ++ ifList cf s) $ cf2data cf
 where
   toArgs (cons,args) = ((cons, names (map (checkRes . var) args) (0 :: Int)), ruleOf cons)
   names [] _ = []
   names (x:xs) n
     | elem x xs = (x ++ show n) : names xs (n+1)
     | otherwise = x             : names xs n
   var ('[':xs)  = var (init xs) ++ "s"
   var "Ident"   = "id"
   var "Integer" = "n"
   var "String"  = "str"
   var "Char"    = "c"
   var "Double"  = "d"
   var xs        = map toLower xs
   checkRes s
        | elem s reservedHaskell = s ++ "'"
	| otherwise              = s
   reservedHaskell = ["case","class","data","default","deriving","do","else","if",
		      "import","in","infix","infixl","infixr","instance","let","module",
		      "newtype","of","then","type","where","as","qualified","hiding"]
   ruleOf s = maybe undefined id $ lookupRule s (rulesOfCF cf)

--- case_fun :: Cat -> [(Constructor,Rule)] -> String
case_fun cat xs = unlines [
  "instance Print" +++ cat +++ "where",
  "  prt i" +++ "e = case e of",
  unlines $ map (\ ((c,xx),r) ->
    "   " ++ c +++ unwords xx +++ "->" +++
    "prPrec i" +++ show (precCat (fst r)) +++ mkRhs xx (snd r)) xs
  ]

ifList cf cat = mkListRule $ nil cat ++ one cat ++ cons cat where
  nil cat  = ["   [] -> " ++ mkRhs [] its |
                            Rule f c its <- rulesOfCF cf, isNilFun f , normCatOfList c == cat]
  one cat  = ["   [x] -> " ++ mkRhs ["x"] its |
                            Rule f c its <- rulesOfCF cf, isOneFun f , normCatOfList c == cat]
  cons cat = ["   x:xs -> " ++ mkRhs ["x","xs"] its |
                            Rule f c its <- rulesOfCF cf, isConsFun f , normCatOfList c == cat]
  mkListRule [] = ""
  mkListRule rs = unlines $ ("  prtList" +++ "es = case es of"):rs


mkRhs args its =
  "(concatD [" ++ unwords (intersperse "," (mk args its)) ++ "])"
 where
  mk args (Left "#" : items)      = mk args items
  mk (arg:args) (Left c : items)  = (prt c +++ arg)        : mk args items
  mk args       (Right s : items) = ("doc (showString" +++ show s ++ ")") : mk args items
  mk _ _ = []
  prt c = "prt" +++ show (precCat c)

