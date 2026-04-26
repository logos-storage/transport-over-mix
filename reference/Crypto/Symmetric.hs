
-- | Symmetric crypto primitives

module Crypto.Symmetric where

--------------------------------------------------------------------------------

-- | Domain separation
data Domain
  = SphinxRouteEncKey           -- ^ key for encrypting the routing header in Sphinx
  | SphinxRouteEncIV            -- ^ initialization vector for header stream cipher (if required)
  | SphinxMacKey                -- ^ key for the MAC in the Sphinx header
  | SphinxPayloadEncKey         -- ^ key to encrypt the Sphinx payload
  | SphinxBlinding              -- ^ key to compute the blinding factor
  deriving (Eq,Show)

-- | Stream ciphers
data StreamCipher
  = AES128_CTR                  -- ^ AES128 in counter mode
  | ChaCha20                    -- ^ ChaCha20
  deriving (Eq,Show )

-- | Key derivation functions
data KDF
  = KDF_SHA256                  -- ^ @SHA256( domain | input )@
  | KDF_TurboShake              -- ^ @TurboShake( domain | input )
  | KDF_HMAC_SHA256             -- ^ HMAC with `key=domain`
  deriving (Eq,Show)

-- | Hash functions
data HashFunction
  = SHA256
  | Blake2b256
  deriving (Eq,Show)

-- | Hash-based message authentication codes
data HMAC
  = HMAC128 HashFunction
  | HMAC256 HashFunction
  deriving (Eq,Show)

-- | Keyed hash functions
data KeyedHash
  = KeyedHash_SHA256_Prepend    -- ^ @SHA256( key | input )@
  | KeyedHash_Blake2b           -- ^ Blake2b support keying natively
  | KeyedHash_HMAC_SHA256                 
  deriving (Eq,Show)

-- | Cipher to encode the Sphinx payload (note: stream ciphers are not a valid choice here!)
data SphinxPayloadCipher
  = Lioness !KeyedHash !StreamCipher
  deriving (Eq,Show)

--------------------------------------------------------------------------------
