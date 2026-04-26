
-- | Public key cryptography (Diffie-Hellman) over X25519

module Crypto.X25519.DH where

--------------------------------------------------------------------------------

import Data.Bits
import Data.Word

import Crypto.X25519.BaseField
import Crypto.X25519.ScalarField
import Crypto.X25519.Elliptic

import Control.Monad
import System.Random

import Octet

--------------------------------------------------------------------------------

sanityDiffieHellman :: IO ()
sanityDiffieHellman = do
  alice <- randomKeyPair
  bob   <- randomKeyPair
  putStrLn $ "Alice: " ++ show alice
  putStrLn $ "Bob:   " ++ show bob
  let sharedAlice = scalarMul (secretKeyToInteger $ fst alice) (pubKeyToGroup $ snd bob  )
  let sharedBob   = scalarMul (secretKeyToInteger $ fst bob  ) (pubKeyToGroup $ snd alice)
  putStrLn $ "shared secret of Alice = " ++ show (xcoordAsWordLE sharedAlice)
  putStrLn $ "shared secret of Bob   = " ++ show (xcoordAsWordLE sharedBob  )
  print (sharedAlice == sharedBob)

--------------------------------------------------------------------------------

-- | 32 bytes, little-endian
newtype PubKey 
  = PK Word256
  deriving (Eq,Show,IsWord)

-- | 32 bytes, little-endian. Warning: Not all such byte vectors are valid secret keys!!
newtype SecretKey 
  = SK Word256
  deriving (Eq,Show,IsWord)

xcoordAsWordLE :: G -> Word256
xcoordAsWordLE pt = fromIntegerLE (xcoordAsInteger pt)

secretKeyToPubKey :: SecretKey -> PubKey
secretKeyToPubKey sk = pubKeyFromGroup g where
  g = scalarMul (secretKeyToInteger sk) basePoint

-- | Clear bits 0, 1, 2 of the first byte, clear bit 7 of the last
-- byte, and set bit 6 of the last byte. (NOTE: it's all little-endian!)
maskSecretKey :: Word256 -> SecretKey
maskSecretKey (W256 bs) = SK (W256 masked) where
  b0  = bs !! 0
  b31 = bs !! 31
  masked =  (b0 .&. 0xf8)
         :  [ bs!!i | i<- [1..30] ]
         ++ [ (b31 .&. 0x7f) .|. 0x40 ]

randomSecretKey :: IO SecretKey
randomSecretKey = do
  bs <- replicateM 32 (randomIO :: IO Word8)
  return (maskSecretKey $ W256 bs)

randomKeyPair :: IO (SecretKey,PubKey) 
randomKeyPair = do
  sk <- randomSecretKey
  let pk = secretKeyToPubKey sk
  return (sk,pk)

--------------------------------------------------------------------------------

pubKeyToGroup :: PubKey -> G
pubKeyToGroup pk = Gx (toFp (pubKeyToInteger pk))

pubKeyFromGroup :: G -> PubKey
pubKeyFromGroup (Gx x) = pubKeyFromInteger (fromFp x)

pubKeyToInteger :: PubKey -> Integer
pubKeyToInteger (PK w) = toIntegerLE w

secretKeyToInteger :: SecretKey -> Integer
secretKeyToInteger (SK w) = toIntegerLE w

pubKeyFromInteger :: Integer -> PubKey
pubKeyFromInteger n = PK (fromIntegerLE n)

secretKeyFromInteger :: Integer -> SecretKey 
secretKeyFromInteger n = SK (fromIntegerLE n)

--------------------------------------------------------------------------------
