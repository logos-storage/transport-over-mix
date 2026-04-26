
-- | The scalar field of Curve25519

module Crypto.X25519.ScalarField where

--------------------------------------------------------------------------------

import System.Random

--------------------------------------------------------------------------------

primeQ :: Integer
primeQ = 2^252 + 27742317777372353535851937790883648493

modQ :: Integer -> Integer
modQ x = mod x primeQ 

newtype Fq
  = Fq Integer 
  deriving (Eq,Show)

fromFq :: Fq -> Integer
fromFq (Fq x) = x

toFq :: Integer -> Fq
toFq n = Fq (modQ n)

instance Num Fq where
  fromInteger  = toFq
  negate (Fq x) = toFq $ negate x
  Fq x + Fq y   = toFq $ x + y
  Fq x - Fq y   = toFq $ x - y
  Fq x * Fq y   = toFq $ x * y
  abs x    = x
  signum _ = Fq 1

randomFqNonZero :: IO Fq
randomFqNonZero = Fq <$> randomRIO (1,primeQ-1)

--------------------------------------------------------------------------------
