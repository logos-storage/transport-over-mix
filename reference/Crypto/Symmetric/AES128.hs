
{-# OPTIONS_GHC -Wno-x-partial #-}
{-# LANGUAGE BangPatterns #-}
module Crypto.Symmetric.AES128 where

--------------------------------------------------------------------------------

import Data.Array.IArray
import Data.Array.Unboxed

import Data.Bits
import Data.Char
import Data.List
import Data.Word
import Data.Int

-- import Text.Printf

import Data.Octets
import Crypto.Types

--------------------------------------------------------------------------------

{-
-- compare to <https://emn178.github.io/online-tools/aes/encrypt/>, it seems to work correctly
-- (also in the case when the nonce is full 128 bits)
key   = Key $ wordFromInteger $ 0x8bf50709c55fb1a5e220e441bc8f5cfa
iv    = IV  $ wordFromInteger $ 0x692854ce7d42ce9b5cad41af00000000
input = replicate 5 (W128 $ replicate 16 97)   -- chr 97 = 'a'
test  = encrypt_AES128CTR key iv input
-}

--------------------------------------------------------------------------------


stream_AES128CTR :: Key -> IV -> [Word128]
stream_AES128CTR key (IV nonce) = map worker [0..] where
  worker :: Word64 -> Word128
  worker counter = aesEncryptBlock key input where
    input = add128 nonce (join64 0 counter)

encrypt_AES128CTR :: Key -> IV -> [Word128] -> [Word128]
encrypt_AES128CTR key iv = zipWith xor128 (stream_AES128CTR key iv)

decrypt_AES128CTR :: Key -> IV -> [Word128] -> [Word128]
decrypt_AES128CTR = encrypt_AES128CTR

aesEncryptBlock :: Key -> Word128 -> Word128
aesEncryptBlock (Key (W128 key)) (W128 input) = W128 output where
  output = encryptBlock' input (keyExpand key)

--------------------------------------------------------------------------------

{-
showHexByte :: Word8 -> String
showHexByte = printf "%02x"

showHex :: [Word8] -> String
showHex = concatMap showHexByte

printHex :: [Word8] -> IO ()
printHex = putStrLn . showHex
-}

--------------------------------------------------------------------------------

-- | Columns of bytes (giving a 4x4 matrix)
type State = [[Word8]]

-- | List of 16 bytes
type RoundKey = [Word8]

encryptBlock' :: [Word8] -> [[Word8]] -> [Word8]
encryptBlock' input roundKeyWords = concat final where

  roundKeys = regroup4 roundKeyWords :: [RoundKey]

  iniState0 = group4 input 
  iniState1 = addRoundKey (head roundKeys) iniState0
   
  preFinal = iterateWith 9 middleStep (tail roundKeys) iniState1
  
  final 
    = addRoundKey (last roundKeys) 
    $ shiftRows 
    $ subBytes 
    $ preFinal

iterateWith :: Int -> (a -> s -> s) -> [a] -> s -> s 
iterateWith n f = go n where
  go  0  _      s = s
  go !k (a:as) !s = go (k-1) as (f a s)
   
--------------------------------------------------------------------------------

middleStep :: RoundKey -> State -> State
middleStep roundkey 
  = addRoundKey roundkey
  . mixColumns
  . shiftRows
  . subBytes

addRoundKey :: RoundKey -> State -> State
addRoundKey roundKey state = zipWith xorList (group4 roundKey) state

shiftRows :: State -> State
shiftRows = transpose . worker . transpose where
  worker = zipWith cycleLeft [0..3] 
  cycleLeft !k xs = drop k xs ++ take k xs
  
subBytes :: State -> State
subBytes = (fmap . fmap) (sbox!)

mixColumns :: State -> State
mixColumns = map mixColumn1
  
mixColumn1 :: [Word8] -> [Word8]
mixColumn1 [a,b,c,d] = 
  [ (mul02 a) `xor` (mul03 b) `xor` (mul01 c) `xor` (mul01 d)
  , (mul01 a) `xor` (mul02 b) `xor` (mul03 c) `xor` (mul01 d)
  , (mul01 a) `xor` (mul01 b) `xor` (mul02 c) `xor` (mul03 d)
  , (mul03 a) `xor` (mul01 b) `xor` (mul01 c) `xor` (mul02 d)
  ]

--------------------------------------------------------------------------------
-- * GF2

-- | multiplies by the polynomial generator @x@ (encoded as @0x02@)
mul_by_x :: Word8 -> Word8
mul_by_x w = case w .&. 0x80 of
  0 ->  shiftL w 1
  _ -> (shiftL w 1) `xor` 0x1b

mul_by_xpowk :: Int -> Word8 -> Word8
mul_by_xpowk = go where
  go  0  w = w
  go !k !w = go (k-1) (mul_by_x w)
   
mulGF2 :: Word8 -> Word8 -> Word8   
mulGF2 x = go 0 x where
  go !acc  _    0 = acc
  go !acc !pow !y = case y .&. 1 of
    0 -> go            acc  (mul_by_x pow) (shiftR y 1)
    _ -> go (pow `xor` acc) (mul_by_x pow) (shiftR y 1)
      
mul01, mul02, mul03 :: Word8 -> Word8 
mul01 a = a
mul02 a =         mul_by_x a
mul03 a = a `xor` mul_by_x a 
      
--------------------------------------------------------------------------------
-- * key expansion

keyExpand :: [Word8] -> [[Word8]]
keyExpand cipherKey = init ++ go 4 (reverse init) where
 
  init = group4 cipherKey 

  go !i ws 
    | i == 44   = []
    | otherwise = new : go (i+1) (new:ws)
    where
      new   = xorList (ws!!3) temp'
      temp  = head ws
      temp' = if mod i 4 /= 0
        then temp
        else xorList (rconst (div i 4)) $ substitute $ rotword $ temp
        
  rotword xs = tail xs ++ [head xs]
  
  rconst :: Int -> [Word8]
  rconst i = [ mul_by_xpowk (i-1) 1 , 0,0,0 ] 
{-
  rconst i 
    | i <=  8 = [ shiftL 1 (i-1) , 0,0,0 ]
    | i ==  9 = [ 0x1b , 0,0,0 ]
    | i == 10 = [ 0x36 , 0,0,0 ]
-}

--------------------------------------------------------------------------------
-- * utils

xorList :: [Word8] -> [Word8] -> [Word8]
xorList = go where
  go []     []     = []
  go (x:xs) (y:ys) = xor x y : go xs ys
  go _      _      = error "xorList: lengths do not match"
  
group4 :: [a] -> [[a]]
group4 = go where
  go [] = []
  go xs = take 4 xs : go (drop 4 xs)
  
regroup4 :: [[a]] -> [[a]]  
regroup4 = go where
  go [] = []
  go xs = concat (take 4 xs) : go (drop 4 xs)
    
--------------------------------------------------------------------------------
-- * examples from the standard

{-

-- | from the standard, Appendix A
exampleCipherKey :: [Word8]
exampleCipherKey = 
  [ 0x2b , 0x7e , 0x15 , 0x16 , 0x28 , 0xae , 0xd2 , 0xa6 
  , 0xab , 0xf7 , 0x15 , 0x88 , 0x09 , 0xcf , 0x4f , 0x3c 
  ]  
  
-- | from the standard, Appendix B
exampleInput :: [Word8]
exampleInput = 
  [ 0x32 , 0x43 , 0xf6 , 0xa8 , 0x88 , 0x5a , 0x30 , 0x8d 
  , 0x31 , 0x31 , 0x98 , 0xa2 , 0xe0 , 0x37 , 0x07 , 0x34 
  ]  
  
-- | from the standard, Appendix B
exampleOutput :: [Word8]
exampleOutput =
  [ 0x39 , 0x25 , 0x84 , 0x1d , 0x02 , 0xdc , 0x09 , 0xfb 
  , 0xdc , 0x11 , 0x85 , 0x97 , 0x19 , 0x6a , 0x0b , 0x32
  ]

-}

--------------------------------------------------------------------------------
-- * S-box

substitute :: Functor f => f Word8 -> f Word8
substitute = fmap (sbox!)

sbox :: UArray Word8 Word8
sbox = listArray (0,255) sboxList

sboxList :: [Word8]
sboxList = 
  [ 0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76
  , 0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0
  , 0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15
  , 0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75
  , 0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84
  , 0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf
  , 0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8
  , 0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2
  , 0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73
  , 0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb
  , 0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79
  , 0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08
  , 0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a
  , 0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e
  , 0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf
  , 0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
  ]

--------------------------------------------------------------------------------


  