{-# OPTIONS_GHC -W #-}
module Parse.Binop (binops, OpTable) where

import Control.Applicative ((<$>))
import qualified Data.List as List
import qualified Data.Map as Map

import SourceSyntax.Annotation (merge)
import qualified SourceSyntax.Expression as E
import SourceSyntax.Declaration (Assoc(..))
import Text.Parsec
import Parse.Helpers

opLevel :: OpTable -> String -> Int
opLevel table op = fst $ Map.findWithDefault (9,L) op table

opAssoc :: OpTable -> String -> Assoc
opAssoc table op = snd $ Map.findWithDefault (9,L) op table

hasLevel :: OpTable -> Int -> (String, E.ParseExpr) -> Bool
hasLevel table n (op,_) = opLevel table op == n

binops :: IParser E.ParseExpr
       -> IParser E.ParseExpr
       -> IParser String
       -> IParser E.ParseExpr
binops term last anyOp =
    do e <- term
       table <- getState
       split table 0 e =<< nextOps
    where
      nextOps = choice [ commitIf (whitespace >> anyOp) $ do
                           whitespace ; op <- anyOp ; whitespace
                           expr <- Left <$> try term <|> Right <$> last
                           case expr of
                             Left t -> (:) (op,t) <$> nextOps
                             Right e -> return [(op,e)]
                       , return [] ]

split :: OpTable
      -> Int
      -> E.ParseExpr
      -> [(String, E.ParseExpr)]
      -> IParser E.ParseExpr
split _ _ e []  = return e
split table n e eops = do
  assoc <- getAssoc table n eops
  es <- sequence (splitLevel table n e eops)
  let ops = map fst (filter (hasLevel table n) eops)
  case assoc of R -> joinR es ops
                _ -> joinL es ops

splitLevel :: OpTable -> Int -> E.ParseExpr -> [(String, E.ParseExpr)]
           -> [IParser E.ParseExpr]
splitLevel table n e eops =
    case break (hasLevel table n) eops of
      (lops, (_op,e'):rops) ->
          split table (n+1) e lops : splitLevel table n e' rops
      (lops, []) -> [ split table (n+1) e lops ]

joinL :: [E.ParseExpr] -> [String] -> IParser E.ParseExpr
joinL [e] [] = return e
joinL (a:b:es) (op:ops) = joinL (merge a b (E.Binop op a b) : es) ops
joinL _ _ = failure "Ill-formed binary expression. Report a compiler bug."

joinR :: [E.ParseExpr] -> [String] -> IParser E.ParseExpr
joinR [e] [] = return e
joinR (a:b:es) (op:ops) = do e <- joinR (b:es) ops
                             return (merge a e (E.Binop op a e))
joinR _ _ = failure "Ill-formed binary expression. Report a compiler bug."

getAssoc :: OpTable -> Int -> [(String,E.ParseExpr)] -> IParser Assoc
getAssoc table n eops
    | all (==L) assocs = return L
    | all (==R) assocs = return R 
    | all (==N) assocs = case assocs of [_] -> return N
                                        _   -> failure (msg "precedence")
    | otherwise = failure (msg "associativity")
  where levelOps = filter (hasLevel table n) eops
        assocs = map (opAssoc table . fst) levelOps
        msg problem =
            concat [ "Conflicting " ++ problem ++ " for binary operators ("
                   , List.intercalate ", " (map fst eops), "). "
                   , "Consider adding parentheses to disambiguate." ]
