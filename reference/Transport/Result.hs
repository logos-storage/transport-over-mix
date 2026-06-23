
-- TODO: move this module somewhere else?

{-# LANGUAGE StrictData, FlexibleInstances, MultiParamTypeClasses, FunctionalDependencies #-}
module Transport.Result where

--------------------------------------------------------------------------------

import Control.Applicative
import Control.Monad
import Control.Monad.Except

--------------------------------------------------------------------------------

type ErrMsg = String

data Result a
  = Ok  a
  | Err ErrMsg
  deriving (Eq,Show)

newtype IOResult a 
  = IOR { runIOResult :: IO (Result a) }

--------------------------------------------------------------------------------

instance Functor IOResult where
  fmap f (IOR action) = IOR $ do
    r <- action
    return $ case r of
      Ok  x -> Ok (f x)
      Err m -> Err m

instance Applicative IOResult where
  pure x = IOR $ pure (Ok x)
  (<*>)  = ap

instance Monad IOResult where
  IOR a >>= u = IOR $ do
    r <- a
    case r of
      Ok  x -> runIOResult (u x)
      Err m -> return (Err m)

instance MonadError ErrMsg IOResult where
  throwError e = IOR $ pure (Err e)
  catchError (IOR action) handler = IOR $ do
    r <- action
    case r of
      Ok  x -> return r
      Err m -> runIOResult (handler m)

--------------------------------------------------------------------------------

