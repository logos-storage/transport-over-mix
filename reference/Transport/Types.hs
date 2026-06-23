
module Transport.Types where

--------------------------------------------------------------------------------

import Data.Word

import qualified Data.ByteString      as B
import qualified Data.ByteString.Lazy as L

import Control.Monad
import System.Random

import Data.Octets

--------------------------------------------------------------------------------

-- | Message index within a session
type MsgIdx = Int -- Word32

-- | Chunk index within a chunked messages
type ChunkIdx = Word16

--------------------------------------------------------------------------------

-- | A (random) session identifier
newtype SessionId
  = MkSessionId [Word8]
  deriving (Eq,Ord)

instance Show SessionId where
  show (MkSessionId xs) = "<session_id = " ++ showHexBytes xs ++ ">"

-- | Session Ids have constant length (16 bytes)
sessionIdSize :: Int
sessionIdSize = 16

randomSessionId :: IO SessionId
randomSessionId = MkSessionId <$> replicateM sessionIdSize randomIO

-- | Here we just look at a SURB as a fixed-sized bytestring
data OpaqueSURB 
  = MkOpaqueSURB B.ByteString
  deriving Eq

instance Show OpaqueSURB where 
  show (MkOpaqueSURB bs) = "<<SURB of size " ++ show (B.length bs) ++ ">>"

type SURB = OpaqueSURB

--------------------------------------------------------------------------------
