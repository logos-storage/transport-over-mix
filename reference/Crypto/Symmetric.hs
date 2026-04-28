
-- | Symmetric crypto primitives

module Crypto.Symmetric where

--------------------------------------------------------------------------------

import Data.Bits
import Data.Word

import qualified Crypto.Symmetric.AES128  as AES128
import qualified Crypto.Symmetric.SHA256  as SHA256
import qualified Crypto.Symmetric.Blake2b as Blake2b
import qualified Crypto.Symmetric.HMAC    as HMac

import Crypto.Types
import Octet

--------------------------------------------------------------------------------

-- | Hash functions
data HashFunction
  = SHA256
  | Blake2b256
  deriving (Eq,Show)

-- | Keyed hash functions
data KeyedHash
  = KeyedHash_SHA256_Prepend    -- ^ @SHA256( key | input )@
  | KeyedHash_Blake2b           -- ^ Blake2b support keying natively
  | KeyedHash_HMAC_SHA256       -- ^ HMAC can be used as a keyed hash function      
  deriving (Eq,Show)

-- | Hash-based message authentication codes
data HMAC
  = HMAC128 HashFunction        -- ^ standard HMAC
  | Blake2bMAC                  
  deriving (Eq,Show)

-- | Stream ciphers
data StreamCipher
  = AES128_CTR                  -- ^ AES128 in counter mode
  | ChaCha20                    -- ^ ChaCha20
  deriving (Eq,Show )

-- | Domain separation (for KDFs)
data Domain
  = SphinxRouteEncKey           -- ^ key for encrypting the routing header in Sphinx
  | SphinxRouteEncIV            -- ^ initialization vector for header stream cipher (if required)
  | SphinxMacKey                -- ^ key for the MAC in the Sphinx header
  | SphinxPayloadEncKey         -- ^ key to encrypt the Sphinx payload
  | SphinxBlinding              -- ^ key to compute the blinding factor
  deriving (Eq,Show)

-- | Key derivation functions
data KDF
  = KDF_SHA256                  -- ^ @SHA256( domain | input )@
  | KDF_TurboShake              -- ^ @TurboShake( domain | input )@
  | KDF_HMAC_SHA256             -- ^ HMAC with @key=domain@
  | KDF_KeyedBlake2b            -- ^ Blake2b with @key=domain@
  deriving (Eq,Show)

-- | Cipher to encode the Sphinx payload (note: stream ciphers are not a valid choice here!)
data SphinxPayloadCipher
  = Lioness !KeyedHash !StreamCipher
  deriving (Eq,Show)

--------------------------------------------------------------------------------

domainConstant :: Domain -> Word128
domainConstant domain = 
  case domain of
    SphinxRouteEncKey   -> asciiStringToWord128 "route-enc-key"
    SphinxRouteEncIV    -> asciiStringToWord128 "route-enc-iv"
    SphinxMacKey        -> asciiStringToWord128 "mac-key"
    SphinxPayloadEncKey -> asciiStringToWord128 "payload-enc-key"
    SphinxBlinding      -> asciiStringToWord128 "sphinx-blinding"
  where 
    asciiStringToWord128 :: String -> Word128
    asciiStringToWord128 input 
      | n <= 16    = W128 (map ord8 input ++ replicate (16-n) 0)
      | otherwise  = error "stringToWord128: input string longer than 16 characters"
      where
        n = length input

domainConstantBytes :: Domain -> [Word8]
domainConstantBytes = fromWord128 . domainConstant

--------------------------------------------------------------------------------

hash :: HashFunction -> [Word8] -> Word256
hash SHA256     = SHA256.sha256
hash Blake2b256 = Blake2b.blake2b 

keyedHash :: KeyedHash -> Key -> [Word8] -> Word256
keyedHash which (Key key) input = case which of
  KeyedHash_SHA256_Prepend  -> SHA256.sha256 (fromWord128 key ++ input) 
  KeyedHash_HMAC_SHA256     -> HMac.genericHMac256 (hash SHA256) (Key key) input
  KeyedHash_Blake2b         -> error "not implemented: KeyedHash_Blake2b"

keyedHash256 :: KeyedHash -> Key -> [Word8] -> Word256
keyedHash256 which (Key key) input = case which of
  KeyedHash_SHA256_Prepend  -> SHA256.sha256 (fromWord128 key ++ input) 
  KeyedHash_HMAC_SHA256     -> HMac.genericHMac256 (hash SHA256) (Key key) input
  KeyedHash_Blake2b         -> error "not implemented: KeyedHash_Blake2b"

hmac :: HMAC -> Key -> [Word8] -> MAC
hmac (HMAC128 hashfun) key msg = MAC $ HMac.genericHMac128 (hash hashfun) key msg

streamCipherEncryptBlocks :: StreamCipher -> Key -> IV -> [Word128] -> [Word128]
streamCipherEncryptBlocks cipher = case cipher of
  AES128_CTR -> AES128.encrypt_AES128CTR
  ChaCha20   -> error "not implemented: ChaCha20"

streamCipherDecryptBlocks :: StreamCipher -> Key -> IV -> [Word128] -> [Word128]
streamCipherDecryptBlocks cipher = case cipher of
  AES128_CTR -> AES128.decrypt_AES128CTR
  ChaCha20   -> error "not implemented: ChaCha20"

streamCipherPRGBlocks :: StreamCipher -> Key -> IV -> [Word128]
streamCipherPRGBlocks cipher = case cipher of
  AES128_CTR -> AES128.stream_AES128CTR
  ChaCha20   -> error "not implemented: ChaCha20"

streamCipherPRGBytes :: StreamCipher -> Key -> IV -> [Word8]
streamCipherPRGBytes cipher key iv = concatMap fromWord128 (streamCipherPRGBlocks cipher key iv)

streamCipherXorBytes :: StreamCipher -> Key -> IV -> [Word8] -> [Word8]
streamCipherXorBytes cipher key iv input = zipWith xor input (streamCipherPRGBytes cipher key iv)

kdf128 :: KDF -> Domain -> [Word8] -> Word128
kdf128 kdf domain input = truncate128 (kdf256 kdf domain input)

kdf256 :: KDF -> Domain -> [Word8] -> Word256
kdf256 kdf domain input = case kdf of
  KDF_SHA256        -> SHA256.sha256 (domainConstantBytes domain ++ input)
  KDF_HMAC_SHA256   -> HMac.genericHMac256 (hash SHA256) (Key $ domainConstant domain) input
  KDF_TurboShake    -> error "not implemented: KDF_TurboShake"
  KDF_KeyedBlake2b  -> error "not implemented: KDF_KeyedBlake2b"

--------------------------------------------------------------------------------
