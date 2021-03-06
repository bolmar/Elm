{-# OPTIONS_GHC -W #-}
module Metadata.Prelude (interfaces, add) where

import qualified Data.Map as Map
import qualified Control.Exception as E
import System.Exit
import System.IO
import SourceSyntax.Module
import qualified Build.Interface as Interface
import Build.Utils (getDataFile)

add :: Bool -> Module def -> Module def
add noPrelude (Module name exs ims decls) = Module name exs (customIms ++ ims) decls
    where
      customIms = if noPrelude then [] else concatMap addModule prelude

      addModule (n, method) = case lookup n ims of
                                Nothing     -> [(n, method)]
                                Just (As _) -> [(n, method)]
                                Just _      -> []

prelude :: [(String, ImportMethod)]
prelude = string ++ text ++ map (\n -> (n, Hiding [])) modules
  where
    text = map ((,) "Text") [ As "Text", Hiding ["link", "color", "height"] ]
    string = map ((,) "String") [ As "String", Importing ["show"] ]
    modules = [ "Basics", "Signal", "List", "Maybe", "Time", "Color"
              , "Graphics.Element", "Graphics.Collage"
              , "Native.Ports", "Native.Json"
              ]

interfaces :: Bool -> IO Interfaces
interfaces noPrelude =
    if noPrelude
    then return Map.empty
    else safeReadDocs =<< getDataFile "interfaces.data"

safeReadDocs :: FilePath -> IO Interfaces
safeReadDocs name =
    E.catch (readDocs name) $ \err -> do
      let _ = err :: IOError
      hPutStrLn stderr $ unlines $
         [ "Error reading types for standard library from file " ++ name
         , "    If you are using a stable version of Elm, please report an issue at"
         , "    <http://github.com/evancz/Elm/issues> specifying version numbers for"
         , "    Elm and your OS." ]
      exitFailure

readDocs :: FilePath -> IO Interfaces
readDocs filePath = do
  interfaces <- Interface.load filePath
  case mapM (Interface.isValid filePath) (interfaces :: [(String, ModuleInterface)]) of
    Left err -> do
      hPutStrLn stderr err
      exitFailure

    Right [] -> do
      hPutStrLn stderr "No interfaces found in serialized Prelude!"
      exitFailure

    Right ifaces -> return $ Map.fromList ifaces
