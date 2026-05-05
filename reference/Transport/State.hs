
-- | State of a connection

{-# LANGUAGE StrictData #-}
module Transport.State where

--------------------------------------------------------------------------------

import Data.IORef

import Data.Map as Map 
import qualified Data.Map as Map

import Transport.Chunks
import Transport.Types

--------------------------------------------------------------------------------

-- | Our role in the protocol
data Role
  = Client                      -- ^ the initiator of the connection
  | Server                      -- ^ the other party in the connection 
  deriving (Eq,Show)

-- | The address of the other party
data ConnAddress 
  = NetworkAddress String       -- ^ we know some kind of address for the other party
  | ReplyToSURB                 -- ^ we don't know their address, instead we can use SURBs to send
  deriving (Eq,Show)

data Connection = MkConnection
  { _connSessionId   :: SessionId                   -- ^ the session id
  , _connRole        :: Role                        -- ^ our role in the connection (client or server)
  , _connDestAddr    :: ConnAddress                 -- ^ the address of the other party
  , _connState       :: IORef ConnectionState       -- ^ current state of the connection
  }

data ConnectionState = MkConnState
  { _connNextSendIdx  :: MsgIdx                      -- ^ index of the next message to send
  , _connNextRecvIdx  :: MsgIdx                      -- ^ index of the next message to receive
  , _connUnusedSURBs  :: [SURB]                      -- ^ set of unused SURBs
  , _connSentMsgState :: Map MsgIdx SentMsgState     -- ^ state of messages we sent
  , _connRecvMsgState :: Map MsgIdx RecvMsgState     -- ^ state of messages we are receiving
  , _connExpectedData :: Maybe Int                   -- ^ number of bytes we are expecting to receive, and haven't sent SURBs for yet
  }  
  deriving (Eq,Show)

-- | State of a message we are sending
data SentMsgState = SentMsgState
  { _origChunks   :: [Chunk]
  , _parityChunks :: [Chunk]
  , _msgStatus    :: SentMsgStatus
  }
  deriving (Eq,Show)

data SentCounter = MkSentCounter
  { _alreadySent  :: Int        -- ^ we already sent this many chunks (0..K-1 means orig; >= K means parity)
  , _needsToSend  :: Int        -- ^ we were asked for this many more chunks
  }        
  deriving (Eq,Show)

data SentMsgStatus
  = SentMsgFailed                           -- ^ the message failed completely; we should probably retransmit  
  | SentMsgSingleton                        -- ^ the message was only a single chunk, so we don't do EC; we can just retransmit
  | SentMsgNeedsMoreChunks SentCounter      -- ^ the other party asked for more chunks
  deriving (Eq,Show)

-- | State of a message we are receiving
data RecvMsgState = RecvMsgState
  { _receivedChunks :: Map ChunkIdx Chunk   -- ^ chunks we received so far
  , _msgNOrigCHunks :: Int                  -- ^ number of original chunks
  }
  deriving (Eq,Show)
  
--------------------------------------------------------------------------------

