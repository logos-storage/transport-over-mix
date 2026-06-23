
-- | Heuristics involved in the transport layer

{-# LANGUAGE StrictData, RecordWildCards, MultiWayIf #-}
module Transport.Heuristics where

--------------------------------------------------------------------------------

import Leopard.Types

import Transport.Protocol
import Transport.Chunks

--------------------------------------------------------------------------------
-- * redundancy settings

data Redundancy 
  = NoRedundancy
  | LowRedundancy
  | MediumRedundancy
  | HighRedundancy
  deriving (Eq,Show)

calculateECParams :: Redundancy -> Int -> ECParams
calculateECParams redundancy k = ECParams k (calculateReservedNChunks redundancy k)

-- | We send out this amount of chunks without waiting for any feedback
calculateInitialNChunks :: Redundancy -> Int -> Int
calculateInitialNChunks redundancy k = 
  case redundancy of
    NoRedundancy       -> k
    LowRedundancy      -> max (k+1) (extra 1.01)
    MediumRedundancy   -> max (k+2) (extra 1.04)
    HighRedundancy     -> max (k+3) (extra 1.10)
  where
    extra s = ceiling (s * fromIntegral k)

-- | However, we generate this many of total chunks initially,
-- so that if a request for more chunks come in, we can just
-- use one of the remaining, without having to retransmit everything
calculateReservedNChunks :: Redundancy -> Int -> Int
calculateReservedNChunks redundancy k = 
  case redundancy of
    NoRedundancy       -> min (2*k) $ max (k+ 5) (extra 1.15)
    LowRedundancy      -> min (2*k) $ max (k+ 8) (extra 1.25)
    MediumRedundancy   -> min (2*k) $ max (k+11) (extra 1.35)
    HighRedundancy     -> min (2*k) $ max (k+15) (extra 1.50)
  where
    extra s = ceiling (s * fromIntegral k)

--------------------------------------------------------------------------------
