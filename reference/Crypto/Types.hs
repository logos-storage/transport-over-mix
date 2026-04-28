
module Crypto.Types where

--------------------------------------------------------------------------------

import Data.Word
import Octet

--------------------------------------------------------------------------------

-- | Symmetric key (128 bits)
newtype Key 
  = Key Word128 
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

--------------------------------------------------------------------------------

macBytes :: MAC -> [Word8]
macBytes (MAC w) = fromWord128 w