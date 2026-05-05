
-- | Erasure coding of chunks

{-# OPTIONS_GHC -Wno-x-partial #-}
{-# LANGUAGE StrictData, RecordWildCards, DerivingVia #-}
module Transport.EC where

--------------------------------------------------------------------------------

import Data.Bits
import Data.Word
import Data.Array
import Data.List
import Data.Ord
import Data.Maybe

import Data.ByteString      (ByteString    ) ; import qualified Data.ByteString      as B
import Data.ByteString.Lazy (LazyByteString) ; import qualified Data.ByteString.Lazy as L

import Control.Monad
import System.IO.Unsafe
import System.Random

import Leopard.Binding
import Leopard.Types
import Leopard.Misc

import Transport.Chunks
import Transport.Types
import Transport.Misc

--------------------------------------------------------------------------------
-- * sanity check "testing"

findCounterExample :: IO ()
findCounterExample = do
  putStrLn "---------------------------------"
  ok <- testEC
  when ok findCounterExample

testEC :: IO Bool
testEC = withLeopard $ do
  sessionId <- randomSessionId
  msgIdx    <- randomRIO (0,99)
  len       <- randomRIO (5000,50000)     -- singleton chunks need to be handled specially...
  payload   <- randomByteString len

  let origChunksArr = chunkMsgPayload sessionId msgIdx payload
  let origChunks    = elems origChunksArr
  let ecK = length origChunks
  let ecM = deterministicParityCount ecK   -- min 5 ecK

  let parityChunks = computeParityChunks' ecM origChunks
  let allChunks    = origChunks ++ parityChunks
  let ecN          = length allChunks

  bad <- randomRIO (0,ecM+1)
  received <- catMaybes <$> maskListRandomly bad allChunks

  -- putStrLn $ "chunks received:"
  -- forM_ received $ \chunk -> do
  --   putStrLn $ " - " ++ show chunk
  -- putStrLn ""

  putStrLn $ "chunks received = " ++ show (map _chunkIndex received)

  let ei = decodeFromChunks received

  putStrLn $ "session id  = " ++ show sessionId
  putStrLn $ "message idx = " ++ show msgIdx
  putStrLn $ "original payload length = " ++ show len
  putStrLn $ "K = " ++ show ecK
  putStrLn $ "M = " ++ show ecM
  putStrLn $ "N = " ++ show ecN ++ " | N == K + M: " ++ show (ecN == ecK + ecM) 
  putStrLn $ "didn't receive = " ++ show bad
  putStrLn $ "did receive    = " ++ show (ecN - bad)
  putStrLn $ "result:"

  fine <- case ei of

    Left  err -> do
      putStrLn $ " - error = " ++ show err
      return (bad > ecM)      

    Right dec -> case dec of
      MkDecodedMessage reSId reIdx bs -> do
        let ok = bs == payload
        putStrLn $ " - recovered session id      = " ++ show reSId
        putStrLn $ " - recovered message idx     = " ++ show reIdx
        putStrLn $ " - recovered payload length  = " ++ show (B.length bs) 
        putStrLn $ " - recovered payload matches = " ++ show ok
        return ok

  return fine

--------------------------------------------------------------------------------

-- | Unfortunately, Leopard doesn't seem to work the way I naively assumed, namely
-- that we can just add parity chunks (up to a limit)
--
-- This is not that suprising: it probably uses the smallest power-of-two subgroup 
-- into which @N = K + M@ fits; so if we vary M, the subgroup can change.
--
-- Hence for any K we just deterministically figure out an M, and always use that.
--
deterministicECParams :: Int -> ECParams
deterministicECParams k = ECParams k n where
  n  = k + m
  m  = min k m'          -- we have the restriction M < K
  m' = if k < 16
    then 8
    else div k 2         -- TODO: finetune this!

deterministicParityCount :: Int -> Int
deterministicParityCount k = let ECParams k' n = deterministicECParams k in (n - k')

--------------------------------------------------------------------------------
-- * EC encoding

computeParityChunks :: [Chunk] -> [Chunk]
computeParityChunks chunks = computeParityChunks' m chunks where
  m = deterministicParityCount (length chunks)

{-# NOINLINE computeParityChunks' #-}
computeParityChunks' :: Int -> [Chunk] -> [Chunk]
computeParityChunks' 0       origChunks  = origChunks 
computeParityChunks' mparity [origChunk] = [origChunk] 
computeParityChunks' mparity origChunks  = 
  case fromChunks origChunks of
    Left  err         -> error err
    Right (meta,ibss) -> case unsafePerformIO (unsafeEncodeIOList ecp $ map snd ibss) of
      Left  err         -> error $ decodeLeopardResult err
      Right bss         -> [ MkChunk meta (fromIntegral j) bs | (j,bs) <- zip [k..] bss ]
  where
    ecp = ECParams k (k+mparity)
    k   = length origChunks
    
--------------------------------------------------------------------------------
-- * EC decoding

data DecodeError
  = NotEnoughChunks Int              -- ^ how many more is required
  | InvalidChunks   String           -- ^ invalid and\/or incompatible set of chunks
  | LeopardError    LeopardResult    -- ^ Leopard reported an error
  | CannotParseMsg                   -- ^ can't parse the decoded bytestring
  deriving (Eq,Show)

data DecodedMessage = MkDecodedMessage
  { _msgSessionId  :: SessionId
  , _msgMessageIdx :: MsgIdx
  , _msgPayload    :: ByteString
  }
  deriving (Eq,Show)

----------------------------------------

{-# NOINLINE decodeFromChunks #-}
decodeFromChunks :: [Chunk] -> Either DecodeError DecodedMessage
decodeFromChunks []     = error "decodeFromChunks: fatal: empty input"
decodeFromChunks chunks = 

  case fromChunks chunks of
    Left  err         -> Left $ InvalidChunks err
    Right (meta,ibss) -> handle meta ibss
  
  where
  
    handle :: ChunkMeta -> [(ChunkIdx,ByteString)] -> Either DecodeError DecodedMessage
    handle meta ibss
      | minIdx < 0        = Left $ InvalidChunks "negative chunk index"
      | maxIdx >= 2*ecK   = Left $ InvalidChunks "too big chunk index (max is 2*K because of Leopard)"
      | repeated_idxs     = Left $ InvalidChunks "repeated chunk indicies"
      | haveCnt < ecK_int = Left $ NotEnoughChunks (ecK_int - haveCnt)
      | otherwise         = case unsafePerformIO (unsafeDecodeIO ecp mbArr) of
          Left  leoRes -> Left (LeopardError leoRes)
          Right arr    -> case parseMsgPayload (B.concat (elems arr)) of
            Nothing      -> Left  $ CannotParseMsg
            Just bs      -> Right $ MkDecodedMessage sessionId msgIdx bs            

      where
        MkChunkMeta sessionId msgIdx ecK = meta
        ecK_int  = fromIntegral ecK                 :: Int
        ecp      = deterministicECParams ecK_int    :: ECParams
        ecM_int  = _ecM ecp                         :: Int
        ecN_int  = _ecN ecp                         :: Int
        haveIdxs = map fst ibss                     :: [ChunkIdx]
        haveCnt  = length  haveIdxs                 :: Int
        minIdx   = minimum haveIdxs                 :: ChunkIdx
        maxIdx   = maximum haveIdxs                 :: ChunkIdx
        -- maxIdxI  = fromIntegral maxIdx              :: Int
        -- ecN_int  = maxIdxI + 1                      :: Int
        repeated_idxs = nubOrd haveIdxs /= sort haveIdxs
        mbArr    = listArray (0,ecN_int-1) (map fun' [0..ecN_int-1])

        fun' :: Int -> Maybe ByteString
        fun' j = fun (fromIntegral j)

        fun :: ChunkIdx -> Maybe ByteString
        fun j    = case find (\(i,bs) -> i == j) ibss of  
          Just (_,bs) -> Just bs
          Nothing     -> Nothing

--------------------------------------------------------------------------------
-- * Shared

-- | Chunks of the same message
fromChunks :: [Chunk] -> Either String (ChunkMeta,[(ChunkIdx,ByteString)])
fromChunks [] = error "fromChunks: fatal: empty input"
fromChunks chunks
  | any (/= chunkMeta) (map _chunkMeta chunks)  = Left $ "fromChunks: chunk metadata differs from each other"
  | otherwise                                   = Right (chunkMeta, map f chunks)
  where
    chunkMeta = _chunkMeta (head chunks)
    f (MkChunk meta idx payload) = (idx, payload)

--------------------------------------------------------------------------------
