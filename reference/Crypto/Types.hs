
module Crypto.Types where

--------------------------------------------------------------------------------

import Data.Word
import Data.Octets

--------------------------------------------------------------------------------

-- | Symmetric key (128 bits)
newtype Key 
  = Key Word128 
  deriving (Eq,Show)

-- | 256-bit symmetric keys
newtype Key256
  = Key256 Word256
  deriving (Eq,Show)

-- | Initialization vector (for stream ciphers; 128 bits)
newtype IV 
  = IV Word128
  deriving (Eq,Show)

-- | Message authentication code (128 bits)
newtype MAC
  = MAC Word128
  deriving (Eq,Show)

type Message = [Word8]

fromKey :: Key -> Word128
fromKey (Key x) = x

fromKey256 :: Key256 -> Word256
fromKey256 (Key256 x) = x

fromIV :: IV -> Word128
fromIV (IV x) = x

--------------------------------------------------------------------------------

macBytes :: MAC -> [Word8]
macBytes (MAC w) = fromWord128 w

----------------------------------------

randomKey :: IO Key
randomKey = (Key . W128) <$> randomBytes 16

randomKeyIV :: IO IV
randomKeyIV = (IV . W128) <$> randomBytes 16

randomKey256 :: IO Key256
randomKey256 = (Key256 . W256) <$> randomBytes 32

--------------------------------------------------------------------------------
