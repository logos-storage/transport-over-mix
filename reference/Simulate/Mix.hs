
-- | Mix simulator

{-# LANGUAGE StrictData #-}
module Simulate.Mix where

--------------------------------------------------------------------------------

import Data.Word

import Simulate.Distributions
import Simulate.DiscreteEvents

--------------------------------------------------------------------------------

type Address = String

data NodeType
  = MixNode
  | ExternalNode
  deriving (Eq,Show)

data CoverTrafficStrategy
  = NoCoverTraffic
  | ConstantRateCoverTraffic Double
  | Poisson
  deriving (Eq,Show)

data GlobalConfig = MkGlobCfg
  { _numberOfMixNodes :: Int 
  , _numberOfExtNodes :: Int
  , _meanDelay        :: Double
  , _coverTraffic     :: CoverTrafficStrategy
  , _epochInSeconds   :: Int                      -- ^ epoch time in seconds                 
  , _ratePerEpoch     :: Int                      -- ^ max number of messages per epoch
  , _networkDropRate  :: Double                   -- ^ percentage of packets dropped by the ambient networking layer 
  }
  deriving (Eq,Show)

--------------------------------------------------------------------------------

-- | Globally unique packet id
type PacketUID = Word64

data Event
  = PacketReceived Address Time PacketUID 

--------------------------------------------------------------------------------

data ExtNodeCfg
  = ExtNodePoisson ExpoDistr
  | ExtNodeSteady  LeftTruncGaussDistr
  deriving Show
  