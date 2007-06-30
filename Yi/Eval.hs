module Yi.Eval (
        -- * Eval\/Interpretation
        evalE,
        msgE',
        jumpToErrorE,
        consoleKeymap,
) where

import Control.Monad
import Control.Monad.Trans
import Data.Array
import GHC.Exts ( unsafeCoerce# )
import Prelude hiding (error)
import System.Directory
import Text.Regex.Posix
import Yi.Core
import Yi.Debug
import Yi.Editor hiding (readEditor)
import Yi.Kernel
import Yi.Keymap
import Yi.Interact hiding (write)
import Yi.Event
import Yi.Buffer

evalToStringE :: String -> YiM String
evalToStringE string = withKernel $ \kernel -> do
  result <- compileExpr kernel ("show (" ++ string ++ ")")
  case result of
    Nothing -> return ""
    Just x -> return (unsafeCoerce# x)

-- | Evaluate some text and show the result in the message line.
evalE :: String -> YiM ()
evalE s = evalToStringE s >>= msgE

-- | Same as msgE, but do nothing instead of printing @()@
msgE' :: String -> YiM ()
msgE' "()" = return ()
msgE' s = msgE s


jumpToE :: String -> Int -> Int -> YiM ()
jumpToE filename line column = do
  bs <- readEditor $ \e -> findBufferWithName e filename -- FIXME: should find by associated file-name
  case bs of
    [] -> do found <- lift $ doesFileExist filename
             if found 
               then fnewE filename
               else error "file not found"
    (b:_) -> switchToBufferOtherWindowE b
  withBuffer $ gotoLn line
  rightOrEolE column


parseErrorMessage :: String -> Maybe (String, Int, Int)
parseErrorMessage ln = do
  result :: (Array Int String) <- ln =~~ "^(.+):([0-9]+):([0-9]+):.*$"
  return (result!1, read (result!2), read (result!3))

parseErrorMessageE :: YiM (String, Int, Int)
parseErrorMessageE = do
  ln <- readLnE 
  let Just location = parseErrorMessage ln
  return location

jumpToErrorE :: YiM ()
jumpToErrorE = do
  (f,l,c) <- parseErrorMessageE
  jumpToE f l c

prompt :: String
prompt = "Yi> "

consoleKeymap :: Keymap
consoleKeymap = do event (Event KEnter [])
                   write $ do x <- readLnE
                              case parseErrorMessage x of
                                Just (f,l,c) -> jumpToE f l c
                                Nothing -> do p <- withBuffer pointB
                                              withBuffer botB
                                              p' <- withBuffer pointB
                                              when (p /= p') $
                                                 insertNE ("\n" ++ prompt ++ x)
                                              insertNE "\n" 
                                              pt <- withBuffer pointB
                                              insertNE "Yi> "
                                              bm <- getBookmarkE "errorInsert"
                                              setBookmarkPointE bm pt
                                              execE $ dropWhile (== '>') $ dropWhile (/= '>') $ x
