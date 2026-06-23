
-- | State machine logic

{-# LANGUAGE StrictData, RecordWildCards, MultiWayIf #-}
module Transport.Logic where

--------------------------------------------------------------------------------

import Data.IORef
import System.IO.Unsafe

import Control.Applicative
import Control.Monad
import Control.Monad.Except

import Data.ByteString as ByteString
import qualified Data.ByteString as B

import Data.Map (Map)  
import qualified Data.Map as Map

import Transport.Protocol
import Transport.Heuristics
import Transport.Chunks
import Transport.State
import Transport.Result
import Transport.Types

--------------------------------------------------------------------------------

-- | Seconds since the start of the protocol. TODO: more proper time representation?
type Time         = Double
type TimeInterval = Double

-- temporary
type TimerInfo = String

type AddrOrSURB = Either SURB NetworkAddress 

data NewConnection = MkNewConnection
  { targetAddress  :: AddrOrSURB                   -- ^ how can we reach the other party
  , targetAppProto :: ApplicationProtocol          -- ^ application level protocol (so that they can understand the request)
  , initialMessage :: Maybe ByteString             -- ^ initial message
  , replyHint      :: Maybe Int                    -- ^ expected reply size, in bytes
  }
  deriving (Eq,Show)

data Event
  = PacketReceived Chunk               -- ^ we received a Mix packet
  | TimerTriggered TimerInfo           -- ^ self-set timer event
  deriving (Eq,Show)

{-
data UserAction
  = UserInitConn  NewConnection        -- ^ the user want to open a new connection
  | UserSend      Message              -- ^ the user wants to send a message
  | UserCloseConn SessionId            -- ^ the user want the close an existing connection
  deriving (Eq,Show)
-}

data Action
  = SendPacket  AddrOrSURB Chunk       -- ^ send a mix packet
  | SignalError ErrMsg                 -- ^ signal some failure toward the user (TODO: proper failure type) 
  | SetTimer    Time TimerInfo         -- ^ set a timer for ourselves 
  deriving (Eq,Show)

--------------------------------------------------------------------------------
-- * open a new connection

data ConnectionOpts = MkConnectionOpts
  { sessionTimeout    :: TimeInterval
  , messageTimeout    :: TimeInterval
  , messageRedundancy :: Redundancy
  }

openConnection :: ConnectionOpts -> NewConnection -> IOResult SessionId
openConnection opts newConn = do
  throwError "not yet implemented"

--------------------------------------------------------------------------------
-- * global state

data LogicState = MkLogicState 
  { openConns :: Map SessionId Connection
  }
  deriving Show

initialLogicState :: LogicState
initialLogicState = MkLogicState
  { openConns = Map.empty
  }

{-# NOINLINE theLogicState #-}
theLogicState :: IORef LogicState
theLogicState = unsafePerformIO $ newIORef initialLogicState

--------------------------------------------------------------------------------

eventHandler :: Event -> IO [Action]
eventHandler event = do
  state <- readIORef theLogicState
  case event of 
    PacketReceived chunk -> packetReceived state chunk
    TimerTriggered timer -> timerTriggered state timer

-- TODO: implement this
timerTriggered :: LogicState -> TimerInfo -> IO [Action]
timerTriggered _ _ = return []

--------------------------------------------------------------------------------
-- * reciving packets

packetReceived :: LogicState -> Chunk -> IO [Action]
packetReceived state@(MkLogicState openConns) chunk@(MkChunk chunkMeta@(MkChunkMeta{..}) chunkIdx chunkData) = do
  case Map.lookup _cmSessionId openConns of

    -- implicitly opened new connection
    Nothing -> do
      newConn <- newRecvConnection _cmSessionId
      let openConns' = Map.insert _cmSessionId newConn openConns
      let state'     = state { openConns = openConns' }
      writeIORef theLogicState state'
      -- now that exists, we can simply reuse the normal handler
      packetReceived state' chunk

    -- existing connection
    Just oldConn@(MkConnection{..}) -> do
      (newConn,actions) <- packetReceived' oldConn chunk 
      let openConns' = Map.insert _cmSessionId newConn openConns
      let state'     = state { openConns = openConns' }
      writeIORef theLogicState state'
      return actions

packetReceived' :: Connection -> Chunk -> IO (Connection, [Action])
packetReceived' conn@(MkConnection{..}) chunk = do
  -- TODO
  undefined

packetReceived'' :: ConnMeta -> ConnectionRecvState -> Chunk -> IO (ConnectionRecvState, [Action])
packetReceived'' connMeta connState chunk@(MkChunk{..}) = do
  -- TODO
  undefined

{-
  let AllCounters ns nr ls lr = _connCounters

  if 
    -- this message was already fully received; we just ignore it
    | msgIdx <= lr   -> return connState

    | Map.notMember msgIdx _connCounters
-}

