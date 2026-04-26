
{-# LANGUAGE ScopedTypeVariables, TypeApplications #-}
module Octet where

--------------------------------------------------------------------------------

import Data.Bits
import Data.Word
import Data.Proxy
import Data.Char

import Control.Monad
import System.Random

import Data.ByteString (ByteString)
import qualified Data.ByteString as B

import Text.Printf

--------------------------------------------------------------------------------

class ByteVec a where
  vecLength  :: Proxy a -> Int
  toBytes    :: a -> [Word8]
  fromBytes  :: [Word8] -> a

toIntegerLE :: ByteVec a => a -> Integer
toIntegerLE = bytesToIntegerLE . toBytes

toIntegerBE :: ByteVec a => a -> Integer
toIntegerBE = bytesToIntegerBE . toBytes

fromIntegerLE :: forall a. ByteVec a => Integer -> a
fromIntegerLE = fromBytes . bytesFromIntegerLE (vecLength (Proxy @a))

fromIntegerBE :: forall a. ByteVec a => Integer -> a
fromIntegerBE = fromBytes . bytesFromIntegerBE (vecLength (Proxy @a))

--------------------------------------------------------------------------------

-- | 128-bit words, stored in Big-Endian order!
newtype Word128 
  = W128 [Word8]
  deriving Eq

-- | 256-bit words, stored in Big-Endian order!
newtype Word256 
  = W256 [Word8]
  deriving Eq

fromWord128 :: Word128 -> [Word8]
fromWord128 (W128 bs) =bs

fromWord256 :: Word256 -> [Word8]
fromWord256 (W256 bs) = bs

instance Show Word128 where show (W128 bs) = showBytes bs
instance Show Word256 where show (W256 bs) = showBytes bs

stringToByteList :: String -> [Word8]
stringToByteList = map readByte . splitString where

  readByte :: String -> Word8
  readByte [a,b] = read ("0x" ++ [a,b])

  splitString :: String -> [String]
  splitString []         = []
  splitString (a:b:rest) = [a,b] : splitString rest
  splitString [_]        = error "stringToByteList: odd length"

stringToWord128 :: String -> Word128
stringToWord128 str 
  | length bs == 16  = W128 bs
  | otherwise        = error "stringToWord128: expecting 32 hex characters"
  where
    bs = stringToByteList str

stringToWord256 :: String -> Word256
stringToWord256 str 
  | length bs == 32  = W256 bs
  | otherwise        = error "stringToWord256: expecting 64 hex characters"
  where
    bs = stringToByteList str

--------------------------------------------------------------------------------
-- TODO: make this nicer...

xor128 :: Word128 -> Word128 -> Word128
xor128 (W128 as) (W128 bs) = W128 (zipWith xor as bs)

xor256 :: Word256 -> Word256 -> Word256
xor256 (W256 as) (W256 bs) = W256 (zipWith xor as bs)

add128 :: Word128 -> Word128 -> Word128
add128 x y = wordFromInteger $ mod (wordToInteger x + wordToInteger y) (2^128)

add256 :: Word256 -> Word256 -> Word256
add256 x y = wordFromInteger $ mod (wordToInteger x + wordToInteger y) (2^256)

join64 :: Word64 -> Word64 -> Word128
join64 hi lo = W128 (toBytesBE hi ++ toBytesBE lo)

join128 :: Word128 -> Word128 -> Word256
join128 hi lo = W256 (fromWord128 hi ++ fromWord128 lo)

split64 :: Word128 -> (Word64, Word64)
split64 (W128 bs) = (fromBytesBE hi, fromBytesBE lo) where (hi, lo) = splitAt 8 bs

split128 :: Word256 -> (Word128, Word128)
split128 (W256 bs) = (fromBytesBE hi, fromBytesBE lo) where (hi, lo) = splitAt 16 bs

rnd128 :: IO Word128
rnd128 = W128 <$> replicateM 16 randomIO 

rnd256 :: IO Word256
rnd256 = W256 <$> replicateM 32 randomIO 

--------------------------------------------------------------------------------

class IsWord a where
  toBytesLE   :: a -> [Word8]
  toBytesBE   :: a -> [Word8]
  fromBytesLE :: [Word8] -> a 
  fromBytesBE :: [Word8] -> a 
  wordToInteger   :: a -> Integer
  wordFromInteger :: Integer -> a
  --
  wordToInteger = bytesToIntegerBE . toBytesBE
  toBytesLE   = reverse . toBytesBE
  toBytesBE   = reverse . toBytesLE
  fromBytesLE = fromBytesBE . reverse
  fromBytesBE = fromBytesLE . reverse

instance IsWord Word32 where
  toBytesLE   = bytesFromIntegerLE 4 . fromIntegral
  fromBytesLE = fromInteger . bytesToIntegerLE 
  wordToInteger   = fromIntegral
  wordFromInteger = fromInteger

instance IsWord Word64 where
  toBytesLE   = bytesFromIntegerLE 8 . fromIntegral
  fromBytesLE = fromInteger . bytesToIntegerLE 
  wordToInteger   = fromIntegral
  wordFromInteger = fromInteger

instance IsWord Word128 where
  toBytesBE       = fromWord128
  fromBytesBE bs  = if length bs == 16 then W128 bs else error "fromBytesBE/Word128: wrong input size"
  wordFromInteger = W128 . bytesFromIntegerBE 16

instance IsWord Word256 where
  toBytesBE      = fromWord256
  fromBytesBE bs = if length bs == 32 then W256 bs else error "fromBytesBE/Word256: wrong input size"
  wordFromInteger = W256 . bytesFromIntegerBE 32

--------------------------------------------------------------------------------

instance ByteVec Word128 where
  vecLength _       = 16
  fromBytes bs      = W128 $ take 16 $ bs ++ repeat 0
  toBytes (W128 bs) = bs

instance ByteVec Word256 where
  vecLength _       = 32
  fromBytes bs      = W256 $ take 32 $ bs ++ repeat 0
  toBytes (W256 bs) = bs

--------------------------------------------------------------------------------
 
bytesToIntegerLE :: [Word8] -> Integer
bytesToIntegerLE = go where
  go []     = 0
  go (b:bs) = fromIntegral b + shiftL (go bs) 8

bytesToIntegerBE :: [Word8] -> Integer
bytesToIntegerBE = bytesToIntegerLE . reverse

bytesFromIntegerLE :: Int -> Integer -> [Word8]
bytesFromIntegerLE = go where
  go 0 0 = []
  go 0 _ = error "bytesFromIntegerLE: does not fit"
  go k x = fromInteger (x .&. 255) : go (k-1) (shiftR x 8)

bytesFromIntegerBE :: Int -> Integer -> [Word8]
bytesFromIntegerBE len x = reverse (bytesFromIntegerLE len x)

--------------------------------------------------------------------------------

showBytes :: [Word8] -> String
showBytes bs = concat [ printf "%02x" b | b <- bs ]

toHexStringLE :: IsWord a => a -> String
toHexStringLE = showBytes . toBytesLE

toHexStringBE :: IsWord a => a -> String
toHexStringBE = showBytes . toBytesBE

ord8 :: Char -> Word8
ord8 = fromIntegral . ord

chr8 :: Word8 -> Char
chr8 = chr . fromIntegral

--------------------------------------------------------------------------------

class ToByteString a where
  toByteStringBE :: a -> ByteString

instance ToByteString Word8 where
  toByteStringBE w = B.singleton w

instance ToByteString Word16 where
  toByteStringBE w = B.pack [ fromIntegral (shiftR w 8) , fromIntegral (w .&. 0xff) ]

instance ToByteString Word32 where
  toByteStringBE w = B.append 
    (toByteStringBE @Word16 (fromIntegral (shiftR w 16 ))) 
    (toByteStringBE @Word16 (fromIntegral (w .&. 0xffff)))

instance ToByteString Word64 where
  toByteStringBE w = B.append 
    (toByteStringBE @Word32 (fromIntegral (shiftR w 32     ))) 
    (toByteStringBE @Word32 (fromIntegral (w .&. 0xffffffff)))

--------------------------------------------------------------------------------

class FromByteString a where
  fromByteStringBE :: ByteString -> (a,ByteString)

fromByteStringBE_ :: FromByteString a => ByteString -> a
fromByteStringBE_ bs = case fromByteStringBE bs of
  (y,rest) -> if B.null rest 
    then y 
    else error "fromByteStringBE_: cannot parse"
    
instance FromByteString Word8 where
  fromByteStringBE bs = case B.unpack (B.take 1 bs) of
    [a] -> ( a , B.drop 1 bs )
    _   -> error "fromByteStringBE/Word8: unexpected end of input"

instance FromByteString Word16 where
  fromByteStringBE bs = case B.unpack (B.take 2 bs) of
    [a,b] -> let y = shiftL (fromIntegral a) 8 .|. (fromIntegral b) 
             in  ( y , B.drop 2 bs )
    _   -> error "fromByteStringBE/Word16: unexpected end of input"

instance FromByteString Word32 where
  fromByteStringBE bs = case B.unpack (B.take 4 bs) of
    [a,b,c,d] -> let y = shiftL (fromIntegral a) 24 .|. 
                         shiftL (fromIntegral b) 16 .|. 
                         shiftL (fromIntegral c)  8 .|. 
                                (fromIntegral d) 
                 in  ( y , B.drop 4 bs )
    _   -> error "fromByteStringBE/Word32: unexpected end of input"

--------------------------------------------------------------------------------
