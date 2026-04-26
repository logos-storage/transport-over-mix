
module Crypto.Symmetric.HMAC where

--------------------------------------------------------------------------------

import Data.Bits
import Data.Word
import Data.Char

import Crypto.Symmetric.SHA256

import Octet
import Crypto.Types

--------------------------------------------------------------------------------

{-
testKey = Key $ fromBytesBE $ map (ord8) "key" ++ replicate 13 0
testMsg = map ord8 "The quick brown fox jumps over the lazy dog"
testMAC = genericHMac256 sha256 testKey testMsg
-- expected result: f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8
-}

--------------------------------------------------------------------------------

type Hash256 = ([Word8] -> Word256)

--------------------------------------------------------------------------------

genericHMac256 :: Hash256 -> Key -> Message -> Word256
genericHMac256 hashfun (Key key) msg = outer where

  outer = hashfun (key_xor_opad ++ toBytesBE inner)

  inner = hashfun (key_xor_ipad ++ msg)

  key_xor_opad = zipWith xor key' opad
  key_xor_ipad = zipWith xor key' ipad

  key' = toBytesBE key ++ replicate 48 0      -- pad with zeros to block size (= 64 bytes)
  opad = replicate 64 0x5c
  ipad = replicate 64 0x36

--------------------------------------------------------------------------------

genericHMac128 :: Hash256 -> Key -> Message -> Word128
genericHMac128 hashfun key msg = fst $ split128 $ genericHMac256 hashfun key msg

--------------------------------------------------------------------------------
