
-- | The base field of Curve25519

module Crypto.X25519.BaseField where

--------------------------------------------------------------------------------

import Data.Bits
import Data.Ratio
import System.Random

--------------------------------------------------------------------------------

primeP :: Integer
primeP = 2^255 - 19

modP :: Integer -> Integer
modP x = mod x primeP

newtype Fp 
  = Fp Integer 
  deriving (Eq,Show)

fromFp :: Fp -> Integer
fromFp (Fp x) = x

toFp :: Integer -> Fp
toFp n = Fp (modP n)

instance Num Fp where
  fromInteger   = toFp
  negate (Fp x) = toFp $ negate x
  Fp x + Fp y   = toFp $ x + y
  Fp x - Fp y   = toFp $ x - y
  Fp x * Fp y   = toFp $ x * y
  abs x    = x
  signum _ = Fp 1

isZero :: Fp -> Bool
isZero (Fp x) = x == 0

pow :: Fp -> Integer -> Fp
pow base expo
  | expo <  0  = pow (inv base) (negate expo)
  | otherwise  = go 1 base expo 
  where
    go :: Fp -> Fp -> Integer -> Fp
    go !acc !s 0  = acc
    go !acc !s !e = case e .&. 1 of
      0 -> go  acc    (s*s) (shiftR e 1)
      1 -> go (acc*s) (s*s) (shiftR e 1)

inv :: Fp -> Fp
inv x = pow x (primeP - 2)

instance Fractional Fp where
  fromRational r = toFp (numerator r) / toFp (denominator r)
  recip = inv
  x / y = x * inv y

randomFp :: IO Fp
randomFp = Fp <$> randomRIO (0,primeP-1)

randomFpNonZero :: IO Fp
randomFpNonZero = Fp <$> randomRIO (1,primeP-1)

--------------------------------------------------------------------------------
