
-- | Discrete event simulation

{-# LANGUAGE BangPatterns, StrictData, ScopedTypeVariables #-}
module Simulate.DiscreteEvents where

--------------------------------------------------------------------------------

import Data.List
import qualified Data.PQueue.Prio.Min as Prio

--------------------------------------------------------------------------------

type Time = Double

type Queue a = Prio.MinPQueue Time a

data Event a = Event
  { eventOccuredAt :: !Time
  , eventPayload   :: !a
  }
  deriving (Eq,Show)

data Action a
  = NewEvent (Event a)
  deriving (Eq,Show)

insertNewEvent :: Action a -> Queue a -> Queue a
insertNewEvent (NewEvent (Event !t !payload)) !queue = Prio.insert t payload queue

insertNewEvents :: [Action a] -> Queue a -> Queue a
insertNewEvents actions !queue = foldl' (flip insertNewEvent) queue actions

--------------------------------------------------------------------------------

type KickStart    s a =                 IO ([Action a],s)
type EventHandler s a = Event a -> s -> IO ([Action a],s)

simulateEvents :: forall s a. KickStart s a -> EventHandler s a -> Time -> IO s
simulateEvents kickStart handler stopTime = 

  do
    (!actions0,!state0) <- kickStart 
    let !queue0 = insertNewEvents actions0 Prio.empty
    go queue0 state0

  where
    go :: Queue a -> s -> IO s
    go !queue !state = case Prio.getMin queue of
      Nothing -> return state
      Just (!time, !payload) -> do
        (!actions, !state') <- handler (Event time payload) state
        let !queue' = insertNewEvents actions queue
        if time <= stopTime
          then go queue' state'
          else return state'

--------------------------------------------------------------------------------
