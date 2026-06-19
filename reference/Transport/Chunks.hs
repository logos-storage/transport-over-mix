
-- | For transporting data not fitting into a single Mix packet, we need
-- to chunk it (ideally with redundancy) 
--

{-# LANGUAGE StrictData, RecordWildCards, DerivingVia #-}
module Transport.Chunks where

--------------------------------------------------------------------------------

import Data.Bits
import Data.Word
import Data.Array

import Data.ByteString      (ByteString    ) ; import qualified Data.ByteString      as B
import Data.ByteString.Lazy (LazyByteString) ; import qualified Data.ByteString.Lazy as L
import Data.Binary
import Data.Binary.Get
import Data.Binary.Put

import Control.Monad

-- import Leopard.Binding
-- import Leopard.Types
import Leopard.Misc

import Transport.Types
import Transport.Misc

--------------------------------------------------------------------------------
-- TODO: move these somewhere else

-- | Payload size including the integerity check @= |delta|@
grossPayloadSize :: Int
grossPayloadSize = 4096 + 16 + 24

-- | Payload size without the integerity check (and other metadata)
netPayloadSize :: Int
netPayloadSize = grossPayloadSize - 16

--------------------------------------------------------------------------------

-- | normally 16 + 8 = 24 bytes
chunkMetaSize :: Int
chunkMetaSize = sessionIdSize + 4 + 2 + 2

-- | Should by divisible by 64 (because of Leopard restriction)
chunkDataSize :: Int
chunkDataSize = netPayloadSize - chunkMetaSize

--------------------------------------------------------------------------------

-- | We prepend the length of the payload, then pad to a multiple of chunk data size,
-- partition into pieces, and prepare each chunk's metadata
chunkMsgPayload :: SessionId -> MsgIdx -> ByteString -> Array Int Chunk
chunkMsgPayload sessionId msgIdx msgPayload = arr where
  padded = buildLazyByteString (putMsgPayload msgPayload)
  m      = fromIntegral (L.length padded)
  (k,0)  = divMod m chunkDataSize
  nOrigs = fromIntegral k
  pieces = partitionLazyByteString chunkDataSize padded
  arr    = listArray (0,k-1) 
             [ MkChunk (MkChunkMeta sessionId msgIdx nOrigs) i (L.toStrict dat) | (i,dat) <- zip [0..] pieces ]

-- | Before chunking, we encoded message payloads by prepending their length (8 bytes), 
-- and then padding with zero bytes. We need to reverse this after recovering from EC chunks
parseMsgPayload :: ByteString -> Maybe ByteString
parseMsgPayload bs = case runGetOrFail getMsgPayload (L.fromStrict bs) of
  Left  _             -> Nothing
  Right (rem, _, out) -> Just out

putMsgPayload :: ByteString -> Put
putMsgPayload rawmsg  = do
  putWord64be   (fromIntegral rawlen)
  putByteString rawmsg
  putByteString (B.replicate padlen 0) 
  where
    padlen = requiredPadToMultipleOf chunkDataSize (rawlen + 8)
    rawlen = B.length rawmsg

getMsgPayload :: Get ByteString
getMsgPayload = do
  len <- getWord64be
  getByteString (fromIntegral len)

partitionLazyByteString :: Int -> L.ByteString -> [L.ByteString]
partitionLazyByteString m = go where
  m64 = fromIntegral m
  go lbs = if L.null lbs 
    then []
    else L.take m64 lbs : go (L.drop m64 lbs)

--------------------------------------------------------------------------------

-- | Note: We don't need the the number of parity chunks, because we think of the parity
-- in a streaming fashion. We send some amount of parity chunks initially, and if the other party
-- doesn't receive enough data to reconstruct, we can simply send more parity chunks
--
data ChunkMeta = MkChunkMeta
  { _cmSessionId    :: SessionId     -- ^ session id
  , _cmMessageIdx   :: Word32        -- ^ message index within the session
  , _cmNOrigChunks  :: Word16        -- ^ K = number of chunks containing the original data
  , _cmNTotalChunks :: Word16        -- ^ N = number total (redundant) chunks
  }
  deriving (Eq,Show)

data Chunk = MkChunk
  { _chunkMeta   :: ChunkMeta     -- ^ metadata shared by all chunks of a message
  , _chunkIndex  :: Word16        -- ^ index of this chunk (0 <= idx < K is original chunk, K >= idx is parity chunk)
  , _chunkData   :: ByteString    -- ^ chunk raw data (usually an EC chunk)
  }
  deriving Eq

instance Show Chunk where
  show (MkChunk meta idx dat) 
    =  "MkChunk"
    ++ " { _chunkMeta = "  ++ show meta
    ++ " ; _chunkIndex = " ++ show idx
    ++ " ; _chunkData = "  ++ showByteString dat
    ++ " }"

--------------------------------------------------------------------------------
-- * Serialization

encodeChunk :: Chunk -> ByteString
encodeChunk = buildStrictByteString . putChunk

buildStrictByteString :: Put -> ByteString
buildStrictByteString = B.toStrict . buildLazyByteString

buildLazyByteString :: Put -> L.ByteString
buildLazyByteString = runPut

putChunk :: Chunk -> Put
putChunk (MkChunk meta idx raw) = do
  putChunkMeta  meta  
  putWord16be   idx
  putByteString raw

putChunkMeta :: ChunkMeta -> Put
putChunkMeta (MkChunkMeta{..}) = do
  putSessionId _cmSessionId 
  putWord32be  _cmMessageIdx 
  putWord16be  _cmNOrigChunks 
  putWord16be  _cmNTotalChunks

putSessionId :: SessionId -> Put
putSessionId (MkSessionId bytes) = mapM_ putWord8 bytes

----------------------------------------
-- * Deserialization

decodeChunk :: ByteString -> Maybe Chunk
decodeChunk = decodeChunkLazy . L.fromStrict

decodeChunkLazy :: LazyByteString -> Maybe Chunk
decodeChunkLazy bs = case runGetOrFail getChunk bs of
  Left  _            -> Nothing
  Right (rem, _, ck) -> if L.null rem
    then Just ck
    else Nothing

getChunk :: Get Chunk
getChunk = MkChunk 
  <$> getChunkMeta 
  <*> getWord16be
  <*> getByteString chunkDataSize

getChunkMeta :: Get ChunkMeta
getChunkMeta = MkChunkMeta
  <$> getSessionId
  <*> getWord32be
  <*> getWord16be
  <*> getWord16be

getSessionId :: Get SessionId
getSessionId = MkSessionId <$> replicateM sessionIdSize getWord8 

--------------------------------------------------------------------------------
