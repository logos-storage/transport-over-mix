
-- | The Lioness "wide block cipher", or pseudo-random permutation (PRP)
--
-- See: 
--
-- * Ross Anderson and Eli Biham: "Two practical and provable secure block ciphers: BEAR and LION"
--

module Crypto.Lioness where

--------------------------------------------------------------------------------

import Data.Bits
import Data.Word

import Crypto.Symmetric     -- for testing only??

import Crypto.Types
import Octet

--------------------------------------------------------------------------------

type ByteStream   = [Word8]
type MasterKey    = Key256

type KeyDerivFun256  = Key256 -> ByteStream
type KeyedHashFun256 = Key256 -> [Word8] -> Word256
type StreamGen256    = Key256 -> ByteStream

data LionessInstance = MkLioness
  { lionessKdfFun  :: KeyDerivFun256
  , lionessHashFun :: KeyedHashFun256
  , lionessCipher  :: StreamGen256
  }

splitKey256 :: Key256 -> (Key,IV)
splitKey256 (Key256 masterKey) = case split128 masterKey of
  (left,right) -> (Key left, IV right)

--------------------------------------------------------------------------------

type LionessKeys = (Key256,Key256,Key256,Key256)

lionessDeriveKeys :: LionessInstance -> MasterKey -> LionessKeys
lionessDeriveKeys (MkLioness kdfFun _ _) masterKey = (k1,k2,k3,k4) where
  [k1,k2,k3,k4] = map (Key256 . W256) $ partition 32 $ take 128 $ kdfFun masterKey

  partition :: Int -> [a] -> [[a]]
  partition m [] = []
  partition m xs = take m xs : partition m (drop m xs)

--------------------------------------------------------------------------------

xorStream :: [Word8] -> ByteStream -> [Word8]
xorStream (x:xs) (y:ys) = xor x y : xorStream xs ys
xorStream []     _      = []
xorStream _      []     = error "xorStream: ran out of the stream"

xorBytes :: [Word8] -> [Word8] -> [Word8]
xorBytes (x:xs) (y:ys) = xor x y : xorBytes xs ys
xorBytes []     []     = []
xorBytes _      _      = error "xorBytes: incompatible lengths"

xorWithKey :: Key256 -> [Word8] -> Key256
xorWithKey (Key256 key) bytes = Key256 $ W256 $ xorBytes bytes (fromWord256 key)

--------------------------------------------------------------------------------

lionessPerm :: LionessInstance -> Key256 -> [Word8] -> [Word8]
lionessPerm inst@(MkLioness kdfFun hashFun streamFun) masterKey input 
  | n < 64     = error "lionessPerm: input is too small (the minimum is 64 bytes)" 
  | otherwise  = l2 ++ r2
  where

    n = length input  

    (k1,k2,k3,k4) = lionessDeriveKeys inst masterKey

    hashFunBytes :: Key256 -> [Word8] -> [Word8]
    hashFunBytes key input = fromWord256 (hashFun key input)

    (l0,r0) = splitAt 32 input

    r1 = r0 `xorStream` streamFun (xorWithKey k1 l0)
    l1 = l0 `xorBytes`  hashFunBytes          k2 r1
    r2 = r1 `xorStream` streamFun (xorWithKey k3 l1)
    l2 = l1 `xorBytes`  hashFunBytes          k4 r2 

lionessInvPerm :: LionessInstance -> Key256 -> [Word8] -> [Word8]
lionessInvPerm inst@(MkLioness kdfFun hashFun streamFun) masterKey input 
  | n < 64     = error "lionessInvPerm: input is too small (the minimum is 64 bytes)" 
  | otherwise  = l2 ++ r2
  where

    n = length input  

    (k1,k2,k3,k4) = lionessDeriveKeys inst masterKey

    hashFunBytes :: Key256 -> [Word8] -> [Word8]
    hashFunBytes key input = fromWord256 (hashFun key input)

    (l0,r0) = splitAt 32 input

    l1 = l0 `xorBytes`  hashFunBytes          k4 r0 
    r1 = r0 `xorStream` streamFun (xorWithKey k3 l1)
    l2 = l1 `xorBytes`  hashFunBytes          k2 r1 
    r2 = r1 `xorStream` streamFun (xorWithKey k1 l2)

--------------------------------------------------------------------------------

twistIV :: IV -> IV
twistIV (IV orig) = IV (orig `xor128` twist) where
  twist = wordFromInteger 0x1234567890abcdef_aa55aa55aa55aa55

testKdfFun :: KeyDerivFun256
testKdfFun bigKey = case splitKey256 bigKey of 
  (key,iv) ->  streamCipherPRGBytes AES128_CTR key (twistIV iv)

testHashFun :: KeyedHashFun256
testHashFun (Key256 bigKey) input = hash SHA256 (fromWord256 bigKey ++ input)

testCipher :: StreamGen256
testCipher bigKey = case splitKey256 bigKey of 
  (key,iv) -> streamCipherPRGBytes AES128_CTR key iv

testInstance :: LionessInstance
testInstance = MkLioness
  { lionessKdfFun  = testKdfFun  
  , lionessHashFun = testHashFun 
  , lionessCipher  = testCipher  
  }

testLioness :: IO ()
testLioness = do
  let n = 137

  key <- randomKey256

  input <- randomBytes n
  let input' = case input of { (b:bs) -> let b' = b `xor` 0x10 in (b':bs) }     -- change one bit

  let output  = lionessPerm testInstance key input
      output' = lionessPerm testInstance key input'

  let re  = lionessInvPerm testInstance key output
      re' = lionessInvPerm testInstance key output'

  putStrLn $ "re  == input   : " ++ show (re  == input )
  putStrLn $ "re' == input'  : " ++ show (re' == input')

  let xorDiff = xorBytes output output'
  let hamming = sum $ map popCount xorDiff
  -- putStrLn $ "output `xor` output'  = " ++ showHexBytes xorDiff
  putStrLn $ "hamming distance between output and output' = " ++ show hamming ++ " (out of " ++ show (8*n) ++ ")"

--------------------------------------------------------------------------------
