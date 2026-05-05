

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
  = InitialMessage
  | Continue
  | CloseSession
  deriving (Eq,Show)

data AckEntry
  = MsgReceived    MsgIdx            -- ^ message received intact
  | MsgFailed      MsgIdx            -- ^ message failed (eg. decoding or checksum)
  | NeedMoreChunks MsgIdx Int        -- ^ we need more chunks 
  deriving (Eq,Show)

--------------------------------------------------------------------------------

data MsgMeta = MkMsgMeta
  { _msgControl  :: SessionControl   -- ^ where we are in the session
  , _msgReqSURBs :: Int              -- ^ how many more SURBs we need 
  , _msgAcks     :: [AckEntry]       -- ^ status of previous messages
  }
  deriving (Eq,Show)

data Message = MkMessage
  { _msgMeta     :: MsgMeta          -- ^ message metadata
  , _msgSURBs    :: [SURB]           -- ^ the new SURBs we send
  , _msgPayload  :: ByteString       -- ^ the actual payload
  }
  deriving Eq

instance Show Message where
  show (MkMessage meta surbs payload) = 
    "MkMessage (" ++ show meta ++ ") " ++ show surbs ++ " " ++ showByteString payload

--------------------------------------------------------------------------------
