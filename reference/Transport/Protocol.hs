

{-# LANGUAGE StrictData, DerivingVia #-}
module Transport.Protocol where

--------------------------------------------------------------------------------

import Data.Word

import Data.ByteString      (ByteString    ) ; import qualified Data.ByteString      as B
import Data.ByteString.Lazy (LazyByteString) ; import qualified Data.ByteString.Lazy as L

import Transport.Types
import Transport.Misc

--------------------------------------------------------------------------------

data SessionControl
  = InitialMessage AppProtocol          -- ^ the first message estabilishing a connection
  | Continue                            -- ^ proceed normally
  | CloseSession                        -- ^ closing down the session
  deriving (Eq,Show,Enum)

-- | Application layer protocol
data AppProtocol = MkAppProtocol
  { appProtocolName :: String           -- ^ name of the application layer protocol
  , appProtocolInfo :: ByteString       -- ^ additional protocol-dependent info (eg. key exchange)
  }
  deriving (Eq,Show)

data AckEntry
  = MsgReceived    MsgIdx               -- ^ message received intact
  | MsgFailed      MsgIdx FailReason    -- ^ message failed (eg. decoding, checksum or timeout)
  | NeedMoreChunks MsgIdx Int           -- ^ we need more chunks 
  | ResendChunks   MsgIdx [Int]         -- ^ re-transmit particular chunks
  deriving (Eq,Show)

data FailReason
  = FailTimeout             -- ^ couldn't decode within the expected time
  | FailDecode              -- ^ erasure code decoding failed
  | FailChecksum            -- ^ checksum failed
  deriving (Eq,Show,Enum)

--------------------------------------------------------------------------------

data MsgMeta = MkMsgMeta
  { _msgControl   :: SessionControl   -- ^ where we are in the session
  , _msgReqSURBs  :: Int              -- ^ how many more SURBs we need 
  , _msgAcks      :: [AckEntry]       -- ^ status of previous messages
  }
  deriving (Eq,Show)

data Message = MkMessage
  { _msgMeta      :: MsgMeta          -- ^ message metadata
  , _msgSURBs     :: [SURB]           -- ^ the new SURBs we send
  , _msgPayload   :: ByteString       -- ^ the actual payload
  }
  deriving Eq

instance Show Message where
  show (MkMessage meta surbs payload) = 
    "MkMessage (" ++ show meta ++ ") " ++ show surbs ++ " " ++ showByteString payload

--------------------------------------------------------------------------------
