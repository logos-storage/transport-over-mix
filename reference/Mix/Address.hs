
-- | Mix address field encoding

{-# LANGUAGE StrictData #-}
module Mix.Address where

--------------------------------------------------------------------------------

import Data.Word

import Control.Monad
import System.Random

import Data.Octets

--------------------------------------------------------------------------------
-- * network addresses

-- | We encode networks addresses as strings for simplicity
type NetworkAddress = String

-- | Compressed mix addresses are something like a hash
newtype ComprMixAddr 
  = MkMixAddr [Word8]
  deriving (Eq,Show)

-- | A mix node can have a full address or a compressed address
data MixAddress 
  = CompressedMixAddr ComprMixAddr
  | FullMixAddr       NetworkAddress
  deriving (Eq,Show)

-- | An address can be a mix node or an external address
data SomeAddress  
  = MixAddress      MixAddress
  | ExternalAddress NetworkAddress
  deriving (Eq,Show)

--------------------------------------------------------------------------------
-- * delays

newtype DelayHint 
  = DelayHint Word16
  deriving (Eq,Show)

randomDelayHint :: IO DelayHint
randomDelayHint = DelayHint <$> randomRIO (1,2^15-1)

--------------------------------------------------------------------------------
-- * mix addresses

data TransportVersion
  = TransportVersion1
  deriving (Eq,Show)

data RecvProtocol
  = BasicMixProtocol                           -- ^ just sending packets
  | MixTransportProtocol TransportVersion      -- ^ it's the transport layer protocol
  deriving (Eq,Show)

data FwdAddress
  = ForwardingHop MixAddress
  | FinalHop      RecvProtocol SomeAddress
  deriving (Eq,Show)

-- | An address field contains a delay hint, and an forwarding address
data AddressField 
  = MkAddressField DelayHint FwdAddress
  deriving (Eq,Show)

--------------------------------------------------------------------------------
