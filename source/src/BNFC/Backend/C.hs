{-
    BNF Converter: C Main file
    Copyright (C) 2004  Author:  Michael Pellauer

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
module BNFC.Backend.C (makeC) where

import BNFC.Utils
import BNFC.CF
import BNFC.Backend.C.CFtoCAbs
import BNFC.Backend.C.CFtoFlexC
import BNFC.Backend.C.CFtoBisonC
import BNFC.Backend.C.CFtoCSkel
import BNFC.Backend.C.CFtoCPrinter
import BNFC.Backend.Latex
import Data.Char
import System.Exit (exitFailure)
import qualified BNFC.Backend.Common.Makefile as Makefile

makeC :: Bool -> String -> CF -> IO ()
makeC make name cf = do
    let (hfile, cfile) = cf2CAbs prefix cf
    writeFileRep "Absyn.h" hfile
    writeFileRep "Absyn.c" cfile
    let (flex, env) = cf2flex prefix cf
    writeFileRep (name ++ ".l") flex
    putStrLn "   (Tested with flex 2.5.31)"
    let bison = cf2Bison prefix cf env
    writeFileRep (name ++ ".y") bison
    putStrLn "   (Tested with bison 1.875a)"
    let header = mkHeaderFile cf (allCats cf) (allEntryPoints cf) env
    writeFileRep "Parser.h" header
    let (skelH, skelC) = cf2CSkel cf
    writeFileRep "Skeleton.h" skelH
    writeFileRep "Skeleton.c" skelC
    let (prinH, prinC) = cf2CPrinter cf
    writeFileRep "Printer.h" prinH
    writeFileRep "Printer.c" prinC
    writeFileRep "Test.c" (ctest cf)
    let latex = cfToLatex name cf
    writeFileRep (name ++ ".tex") latex
    if make then (writeFileRep "Makefile" $ makefile name prefix) else return ()
  where prefix :: String  -- The prefix is a string used by flex and bison
                          -- that is prepended to generated function names.
                          -- In most cases we want the grammar name as the prefix
                          -- but in a few specific cases, this can create clashes
                          -- with existing functions
        prefix = if name `elem` ["m","c","re","std","str"]
          then (name ++ "_")
          else name

makefile :: String -> String -> String
makefile name prefix =
  (++) (unlines [ "CC = gcc",
                  "CCFLAGS = -g -W -Wall", "",
                  "FLEX = flex",
                  "FLEX_OPTS = -P" ++ prefix, "",
                  "BISON = bison",
                  "BISON_OPTS = -t -p" ++ prefix, ""])
  $ Makefile.mkRule ".PHONY" ["clean", "distclean"]
    []
  $ Makefile.mkRule "all" [testName]
    []
  $ Makefile.mkRule "clean" []
    -- peteg: don't nuke what we generated - move that to the "vclean" target.
    [ "rm -f *.o " ++ unwords [ name ++ e | e <- [".aux",".log",".pdf",""]] ]
  $ Makefile.mkRule "distclean" ["clean"] -- FIXME
    [ "rm -f " ++ unwords
      [ "Absyn.c", "Absyn.h", "Test.c", "Parser.c", "Parser.h", "Lexer.c"
      , "Skeleton.c", "Skeleton.h", "Printer.c" ,"Printer.h"
      , name ++ ".l " ++ name ++ ".y " ++ name ++ ".tex "
      , testName, "Makefile" ]]
  $ Makefile.mkRule testName ["Absyn.o", "Lexer.o", "Parser.o", "Printer.o", "Test.o"]
    [ "@echo \"Linking test" ++ name ++ "...\""
    , "${CC} ${CCFLAGS} *.o -o Test" ++ name ]
  $ Makefile.mkRule "Absyn.o" [ "Absyn.c", "Absyn.h"]
    [ "${CC} ${CCFLAGS} -c Absyn.c" ]
  $ Makefile.mkRule "Lexer.c" [ name ++ ".l" ]
    [ "${FLEX} ${FLEX_OPTS} -oLexer.c " ++ name ++ ".l" ]
  $ Makefile.mkRule "Parser.c" [ name ++ ".y" ]
    [ "${BISON} ${BISON_OPTS} " ++ name ++ ".y -o Parser.c" ]
  $ Makefile.mkRule "Lexer.o" [ "Lexer.c", "Parser.h" ]
    [ "${CC} ${CCFLAGS} -c Lexer.c " ]
  $ Makefile.mkRule "Parser.o" ["Parser.c", "Absyn.h" ]
    [ "${CC} ${CCFLAGS} -c Parser.c" ]
  $ Makefile.mkRule "Printer.o" [ "Printer.c", "Printer.h", "Absyn.h" ]
    [ "${CC} ${CCFLAGS} -c Printer.c" ]
  $ Makefile.mkRule "Test.o" [ "Test.c", "Parser.h", "Printer.h", "Absyn.h" ]
    [ "${CC} ${CCFLAGS} -c Test.c" ]
  $ Makefile.mkDoc (name ++ ".tex")
  ""
  where testName = "Test" ++ name

ctest :: CF -> String
ctest cf =
  unlines
   [
    "/*** Compiler Front-End Test automatically generated by the BNF Converter ***/",
    "/*                                                                          */",
    "/* This test will parse a file, print the abstract syntax tree, and then    */",
    "/* pretty-print the result.                                                 */",
    "/*                                                                          */",
    "/****************************************************************************/",
    "",
    "#include <stdio.h>",
    "#include <stdlib.h>",
    "",
    "#include \"Parser.h\"",
    "#include \"Printer.h\"",
    "#include \"Absyn.h\"",
    "",
    "int main(int argc, char ** argv)",
    "{",
    "  FILE *input;",
    "  " ++ def ++ " parse_tree;",
    "  if (argc > 1) ",
    "  {",
    "    input = fopen(argv[1], \"r\");",
    "    if (!input)",
    "    {",
    "      fprintf(stderr, \"Error opening input file.\\n\");",
    "      exit(1);",
    "    }",
    "  }",
    "  else input = stdin;",
    "  /* The default entry point is used. For other options see Parser.h */",
    "  parse_tree = p" ++ def ++ "(input);",
    "  if (parse_tree)",
    "  {",
    "    printf(\"\\nParse Succesful!\\n\");",
    "    printf(\"\\n[Abstract Syntax]\\n\");",
    "    printf(\"%s\\n\\n\", show" ++ def ++ "(parse_tree));",
    "    printf(\"[Linearized Tree]\\n\");",
    "    printf(\"%s\\n\\n\", print" ++ def ++ "(parse_tree));",
    "    return 0;",
    "  }",
    "  return 1;",
    "}",
    ""
   ]
  where
   def = head (allEntryPoints cf)

mkHeaderFile :: CF -> [Cat] -> [Cat] -> [(a, String)] -> String
mkHeaderFile cf cats eps env = unlines
 [
  "#ifndef PARSER_HEADER_FILE",
  "#define PARSER_HEADER_FILE",
  "",
  "#include \"Absyn.h\"",
  "",
  "typedef union",
  "{",
  "  int int_;",
  "  char char_;",
  "  double double_;",
  "  char* string_;",
  (concatMap mkVar cats) ++ "} YYSTYPE;",
  "",
  "#define _ERROR_ 258",
  mkDefines (259::Int) env,
  "extern YYSTYPE yylval;",
  concatMap mkFunc eps,
  "",
  "#endif"
 ]
 where
  mkVar s | (normCat s == s) = "  " ++ (identCat s) +++ (map toLower (identCat s)) ++ "_;\n"
  mkVar _ = ""
  mkDefines n [] = mkString n
  mkDefines n ((_,s):ss) = ("#define " ++ s +++ (show n) ++ "\n") ++ (mkDefines (n+1) ss)
  mkString n =  if isUsedCat cf "String"
   then ("#define _STRING_ " ++ show n ++ "\n") ++ mkChar (n+1)
   else mkChar n
  mkChar n =  if isUsedCat cf "Char"
   then ("#define _CHAR_ " ++ show n ++ "\n") ++ mkInteger (n+1)
   else mkInteger n
  mkInteger n =  if isUsedCat cf "Integer"
   then ("#define _INTEGER_ " ++ show n ++ "\n") ++ mkDouble (n+1)
   else mkDouble n
  mkDouble n =  if isUsedCat cf "Double"
   then ("#define _DOUBLE_ " ++ show n ++ "\n") ++ mkIdent(n+1)
   else mkIdent n
  mkIdent n =  if isUsedCat cf "Ident"
   then ("#define _IDENT_ " ++ show n ++ "\n")
   else ""
  mkFunc s | (normCat s == s) = (identCat s) ++ " p" ++ (identCat s) ++ "(FILE *inp);\n"
  mkFunc _ = ""

