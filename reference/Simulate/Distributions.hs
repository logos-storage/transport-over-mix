
-- | Probability distributions

{-# LANGUAGE BangPatterns, StrictData #-}
module Simulate.Distributions where

--------------------------------------------------------------------------------

import Data.List

import Control.Monad
import System.Random

--------------------------------------------------------------------------------

class Distribution distrib where
  sample  :: distrib -> IO Double
  sample2 :: distrib -> IO (Double,Double)
  
  sample  distrib = fst <$> sample2 distrib
  sample2 distrib = do
    x <- sample distrib
    y <- sample distrib
    return (x,y)

sampleN :: Distribution distrib => distrib -> Int -> IO [Double]
sampleN distrib n = replicateM n (sample distrib)

--------------------------------------------------------------------------------

-- | Diract delta distribution, defined by its support value
data DiracDelta
  = DiracDelta Double          
  deriving (Show)

-- | Exponential distribution defined by its mean
data ExpoDistr 
  = ExpoDistr Double          
  deriving (Show)

-- | Truncated exponential distribution defined by its maximum and the underlying exponential
data TruncExpoDistr 
  = TruncExpoDistr Double ExpoDistr           
  deriving (Show)

-- | Bi-truncated exponential distribution defined by its minimum, maximum and the underlying exponential
data BiTruncExpoDistr 
  = BiTruncExpoDistr (Double,Double) ExpoDistr
  deriving (Show)

-- | Gaussian distribution defined by its mean and standard deviation
data GaussDistr
  = GaussDistr Double Double
  deriving (Show)

-- | Gaussian distribution, but truncated from the left 
data LeftTruncGaussDistr
  = LeftTruncGaussDistr Double GaussDistr
  deriving (Show)

----------------------------------------

instance Distribution DiracDelta where 
  sample (DiracDelta x) = return x

instance Distribution ExpoDistr where 
  sample (ExpoDistr mean) = do 
    u <- randomIO 
    return (- mean * log u)

instance Distribution TruncExpoDistr where 
  sample (TruncExpoDistr maximum expo) = loop where
    loop = do 
      y <- sample expo
      if y < maximum
        then return y
        else loop

instance Distribution BiTruncExpoDistr where 
  sample (BiTruncExpoDistr (minimum,maximum) expo) = loop where
    loop = do 
      y <- sample expo
      if y > minimum && y < maximum
        then return y
        else loop

instance Distribution GaussDistr where 
  -- Marsaglia polar method 
  sample2 distrib@(GaussDistr mean dev) = do
    u <- randomRIO (-1,1)
    v <- randomRIO (-1,1)
    let s = u*u + v*v
    if s >= 1 
      then sample2 distrib
      else do
        let w = sqrt ( - 2*log s / s )
        let x = u*w
        let y = v*w
        return (mean + x*dev , mean + y*dev)

instance Distribution LeftTruncGaussDistr where 
  sample (LeftTruncGaussDistr minimum gauss) = loop where
    loop = do
      y <- sample gauss
      if y > minimum 
        then return y
        else loop

--------------------------------------------------------------------------------

average :: [Double] -> Double
average xs = sum xs / fromIntegral (length xs)

variance :: [Double] -> Double
variance xs = average y2s where
  y2s = [ y*y | x<-xs, let y = x-a ] 
  a = average xs

deviation :: [Double] -> Double
deviation = sqrt . variance

--------------------------------------------------------------------------------
