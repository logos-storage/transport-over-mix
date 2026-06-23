
-- | State of a connection

{-# LANGUAGE StrictData, PatternSynonyms, FlexibleInstances #-}
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

-- | Network addresses here we encode as strings, for simplicity
type NetworkAddress = String

-- | The address of the other party
data ConnAddress 
  = NetworkAddr NetworkAddress      -- ^ we know some kind of address for the other party
  | ReplyToSURB                     -- ^ we don't know their address, instead we can use SURBs to send
  deriving (Eq,Show)

newtype ApplicationProtocol 
  = MkAppProto String
  deriving (Eq,Show)

data ConnMeta = MkConnMeta
  { _connRole        :: Role                        -- ^ our role in the connection (client or server)
  , _connAppProto    :: Maybe ApplicationProtocol   -- ^ application layer protocol
  , _connDestAddr    :: ConnAddress                 -- ^ the address of the other party
  }
  deriving (Eq,Show)

defaultServerConnMeta :: ConnMeta
defaultServerConnMeta = MkConnMeta
  { _connRole     = Server
  , _connAppProto = Nothing
  , _connDestAddr = ReplyToSURB
  }

data Connection = MkConnection
  { _connSessionId   :: SessionId                   -- ^ the session id
  , _connMeta        :: ConnMeta                    -- ^ connection metadata
  , _connStateRef    :: IORef ConnectionState       -- ^ current state of the connection
  }
  deriving (Show)

instance Show (IORef ConnectionState) where
  show _ = "<<IORef ConnectionState>>"

newRecvConnection :: SessionId -> IO Connection
newRecvConnection sessionId = do
  stateRef <- newIORef emptyConnectionState
  return $ MkConnection
    { _connSessionId = sessionId
    , _connMeta      = defaultServerConnMeta
    , _connStateRef  = stateRef
    }

-- | Message index counters for sent messages
data SentCounters = MkSentCounters
  { _ctrLastFullyAckIdx  :: MsgIdx       -- ^ index of the last message fully sent and acknowledged
  , _ctrNextSendIdx      :: MsgIdx       -- ^ index of the next message to send
  }
  deriving (Eq,Show)

-- | Message index counters for received messages
data RecvCounters = MkRecvCounters
  { _ctrLastFullyRecvIdx :: MsgIdx       -- ^ index of the last message fully received
  , _ctrNextRecvIdx      :: MsgIdx       -- ^ index of the next message to receive
  }
  deriving (Eq,Show)

emptySentCounters :: SentCounters
emptySentCounters = MkSentCounters (-1) 0

emptyRecvCounters :: RecvCounters
emptyRecvCounters = MkRecvCounters (-1) 0

data ConnectionSentState = MkConnSentState
  { sentCounters       :: SentCounters               -- ^ message index counters
  , sentUnusedFwdSURBs :: [SURB]                     -- ^ set of unused SURBs we can use
  , sentMsgState       :: Map MsgIdx SentMsgState    -- ^ state of messages we sent
  , sentExpectedBytes  :: Maybe Int                  -- ^ number of bytes we are expecting to send, and haven't yet asked fwdSURBs for 
  }
  deriving (Eq,Show)

data ConnectionRecvState = MkConnRecvState
  { recvCounters       :: RecvCounters               -- ^ message index counters
  , recvUnusedBwdSURBs :: [SURB]                     -- ^ set of unused SURBs we can send (this can be always refreshed)
  , recvMsgState       :: Map MsgIdx RecvMsgState    -- ^ state of messages we are receiving
  , recvExpectedBytes  :: Maybe Int                  -- ^ number of bytes we are expecting to receive, and haven't yet sent bwdSURBs for
  }  
  deriving (Eq,Show)

data ConnectionState = MkConnState
  { connSentState :: ConnectionSentState
  , connRecvState :: ConnectionRecvState
  }  
  deriving (Eq,Show)

emptyConnectionSentState :: ConnectionSentState
emptyConnectionSentState = MkConnSentState
  { sentCounters       = emptySentCounters
  , sentUnusedFwdSURBs = []
  , sentMsgState       = Map.empty
  , sentExpectedBytes  = Nothing
  }  

emptyConnectionRecvState :: ConnectionRecvState
emptyConnectionRecvState = MkConnRecvState
  { recvCounters       = emptyRecvCounters
  , recvUnusedBwdSURBs = []
  , recvMsgState       = Map.empty
  , recvExpectedBytes  = Nothing
  }  

emptyConnectionState :: ConnectionState
emptyConnectionState = MkConnState
  { connSentState = emptyConnectionSentState
  , connRecvState = emptyConnectionRecvState
  }  

-- | State of a message we are sending
data SentMsgState = SentMsgState
  { _origChunks   :: [Chunk]
  , _parityChunks :: [Chunk]
  , _msgStatus    :: SentMsgStatus
  }
  deriving (Eq,Show)

data SentChunkCounter = MkSentChunkCounter
  { _alreadySent  :: Int        -- ^ we already sent this many chunks (0..K-1 means orig; >= K means parity)
  , _needsToSend  :: Int        -- ^ we were asked for this many more chunks
  }        
  deriving (Eq,Show)

data SentMsgStatus
  = SentMsgFailed                               -- ^ the message failed completely; we should probably retransmit  
  | SentMsgSingleton                            -- ^ the message was only a single chunk, so we don't do EC; we can just retransmit
  | SentMsgNeedsMoreChunks SentChunkCounter     -- ^ the other party asked for more chunks
  deriving (Eq,Show)

-- | State of a message we are receiving
data RecvMsgState = RecvMsgState
  { _receivedChunks  :: Map ChunkIdx Chunk   -- ^ chunks we received so far
  , _msgNOrigChunks  :: Int                  -- ^ number of original chunks
  , _msgNTotalChunks :: Int                  -- ^ number of total chunks (original + parity)
  }
  deriving (Eq,Show)
  
--------------------------------------------------------------------------------

