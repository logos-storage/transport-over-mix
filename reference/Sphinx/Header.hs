
-- | The Sphinx packet format header.
--
-- See:
--
-- * George Danezis, Ian Goldberg: "Sphinx: A Compact and Provably Secure Mix Format"
--   <https://cypherpunks.ca/~iang/pubs/Sphinx_Oakland09.pdf>
--
-- * see also the @docs@ subdirectory in this repo
--

{-# OPTIONS_GHC -Wno-x-partial #-}
{-# LANGUAGE DeriveGeneric, TypeApplications #-}
module Sphinx.Header where

--------------------------------------------------------------------------------

import Data.Bits
import Data.Word
import Data.Semigroup
import Data.Monoid

import Control.Monad
import System.Random

import qualified Data.ByteString      as B
import qualified Data.ByteString.Lazy as L
import GHC.Generics
import Data.Binary

import Crypto.X25519.DH
import Crypto.X25519.Elliptic
import Crypto.X25519.ScalarField ( Fq , toFq )

import Crypto.Symmetric
import Crypto.Types

import Data.Octets

--------------------------------------------------------------------------------
-- * global constants

-- | Maximum number of hops
maxNumberOfHops :: Int
maxNumberOfHops = 5

{-
-- | Targeted security in bits = size of symmetric keys = size of MACs = half the size of private keys
lambda :: Int
lambda = 128

lambdaBytes :: Int
lambdaBytes = div lambda 8
-}

--------------------------------------------------------------------------------
-- * crypto primitives

mixKDF :: Domain -> [Word8] -> Word128
mixKDF = kdf128 KDF_SHA256

mixMAC :: Key -> [Word8] -> MAC
mixMAC = hmac (HMAC128 SHA256)

mixPRG :: Key -> IV -> [Word8]
mixPRG = streamCipherPRGBytes AES128_CTR 

mixRouteEncDec :: Key -> IV -> [Word8] -> [Word8]
mixRouteEncDec key iv input = zipWith xor input (mixPRG key iv)


--------------------------------------------------------------------------------
-- * types

-- | Size of something measured in bytes
type SizeInBytes = Int

-- | The actual number of hops. Can be less or equal to @maxNumberOfHops@.
type NHops = Int

{-
-- | A destination address is usually outside the mix network. We represent it by
-- a string (padded to a fixed length)
type DestinationAddr = String

-- | A compressed mix node address should be represented as a fixed length bytestring
newtype ComprMixAddr 
  = MkMixAddr [Word8]
  deriving (Eq,Show)

-- | A (random) message identifier, to identify replies. 
type MessageId = Word128

data Address
  = ForwardDestination !DestinationAddr
  | ReplyDestination   !DestinationAddr
  | MixNode            !MixAddr
  deriving (Eq,Show)
-}

-- | A mix node (extenal view) has a public key and an address
data MixNodeExt addr = MkMixNodeExt
  { nodePubKey  :: PubKey
  , nodeAddress :: addr
  }
  deriving (Eq,Show)

-- | Internally, a mix node also has a private key (required for processing)
data MixNodeInt addr = MkMixNodeInt
  { nodePrivKey :: SecretKey 
  , nodeExt     :: MixNodeExt addr 
  }
  deriving (Eq,Show)

-- | A mix path is a route consisting of several mix nodes
type MixPath addr = [MixNodeInt addr]

-- | A Sphinx header consists of three part, denoted (after the Sphinx paper) by alpha, beta, and gamma.
data SphinxHeader = MkHeader
  { sphinxAlpha :: PubKey           -- ^ blinded per-hop public key
  , sphinxBeta  :: [Word8]          -- ^ encrypted routing info
  , sphinxGamma :: MAC              -- ^ MAC of beta
  }
  deriving (Eq) -- ,Show)

instance Show SphinxHeader where
  show (MkHeader alpha beta gamma) = unlines
    [ "alpha = " ++ show alpha
    , "beta  = " ++ showHexBytes beta
    , "gamma = " ++ show gamma
    ]

--------------------------------------------------------------------------------
-- * per-hop secrets

data PerHopSecrets = MkPerHopSecrets
  { hopSecretKey      :: SecretKey     -- ^ per-node secret key @x@ (an element of the scalar field)
  , hopPublicKey      :: PubKey        -- ^ per-node public key @alpha@ (an element of the elliptic curve group)
  , hopSharedSecret   :: Word256       -- ^ per-node shared secret @s@ (a group element interpreted as 32 bytes)
  , hopBlindingFactor :: Fq            -- ^ the blinding factor @b@ is also an element of the scalar field
  }
  deriving (Eq,Show)

-- TODO: really the blinder should be computed by a "proper" KDF, but everybody out there just uses plain SHA256...
computeBlinder :: PubKey -> Word256 -> Integer
computeBlinder alpha sharedSecret = toIntegerLE blinder where
  blindInput  = pubKeyBytes alpha ++ fromWord256 sharedSecret :: [Word8]
  blinder     = hash SHA256 blindInput                        :: Word256 

computePerHopSecrets :: SecretKey -> [MixNodeExt addr] -> [PerHopSecrets]
computePerHopSecrets initialSecret path = go initialSecret path where
  go :: SecretKey -> [MixNodeExt addr] -> [PerHopSecrets]
  go _ []             = []
  go x (mixnode:rest) = this : go x' rest where
    alpha       = secretKeyToPubKey x                                :: PubKey
    shared      = diffieHellmanSharedSecret x (nodePubKey mixnode)   :: Word256
    blindInput  = pubKeyBytes alpha ++ fromWord256 shared            :: [Word8]
    blinder     = computeBlinder alpha shared                        :: Integer
    x' = blindSecretKey blinder x
    this = MkPerHopSecrets
      { hopSecretKey      = x
      , hopPublicKey      = alpha
      , hopSharedSecret   = shared
      , hopBlindingFactor = toFq blinder
      }

--------------------------------------------------------------------------------
-- * filler strings

newtype Filler 
  = Filler [Word8]
  deriving (Eq)

instance Show Filler where
  show (Filler bs) = "<" ++ showHexBytes bs ++ ">"

fromFiller :: Filler -> [Word8]
fromFiller (Filler ws) = ws

emptyFiller :: Filler
emptyFiller = Filler []

zeroFiller :: SizeInBytes -> Filler
zeroFiller len = Filler $ replicate len 0

fillerSize :: Filler -> SizeInBytes
fillerSize (Filler bs) = length bs

instance Semigroup Filler where
  (<>) (Filler ws1) (Filler ws2) = Filler (ws1 ++ ws2)

instance Monoid Filler where
  mempty = emptyFiller

-- | compute the both the unencrypted (plain) and encrypted fillers
computeAllFillers :: SizeInBytes -> [(PerHopSecrets,SizeInBytes)] -> [Filler]
computeAllFillers headerBetaSize hops 
  | padding < 0  = error "computeFillers: cannot fit in the given header beta size"
  | otherwise    = go emptyFiller hops 
  where
    used    = sum (map snd hops)
    padding = headerBetaSize - used

    go :: Filler -> [(PerHopSecrets,SizeInBytes)] -> [Filler]
    go prev []                   = []
    go prev ((perhop,size):rest) = prev : go this rest where
      ss  = fromWord256 $ hopSharedSecret perhop
      key = Key (mixKDF SphinxRouteEncKey ss)
      iv  = IV  (mixKDF SphinxRouteEncIV  ss) 
      thisPlain = fromFiller (prev <> zeroFiller size)  
      this      = Filler $ zipWith xor thisPlain (drop padlen $ mixPRG key iv)
      padlen    = headerBetaSize - fillerSize prev

computeFinalFiller ::  SizeInBytes -> [(PerHopSecrets,SizeInBytes)] -> Filler
computeFinalFiller headerBetaSize perHops = last $ computeAllFillers headerBetaSize perHops

--------------------------------------------------------------------------------
-- * constructing mix headers

encodeIntoBytes :: Binary a => a -> [Word8]
encodeIntoBytes = L.unpack . encode 

decodeFromBytes :: Binary a => [Word8] -> Maybe (a, SizeInBytes, [Word8])
decodeFromBytes what = case decodeOrFail (L.pack what) of
  Left _              -> Nothing
  Right (rest,size,y) -> Just (y, fromIntegral size, L.unpack rest)

computeHeaderGeneric :: Binary route => SizeInBytes -> [(PerHopSecrets,route)] -> SphinxHeader
computeHeaderGeneric betaSize hops = head $ computeAllHeadersGeneric betaSize hops

data NextBeta
  = NextBeta  { _nextBeta :: [Word8] , _nextMac    :: [Word8] }      -- ^ @beta, gamma@
  | FinalBeta { _nextBeta :: [Word8] , _nextFiller :: Filler  }      -- ^ @beta, filler@
  deriving Show

computeAllHeadersGeneric :: Binary route => SizeInBytes -> [(PerHopSecrets,route)] -> [SphinxHeader]
computeAllHeadersGeneric headerBetaSize hops
  | sum sizes > headerBetaSize  = error "computeHeadersGeneric: total route size is larger than the header beta size"
  | otherwise                   = reverse $ worker finalBeta $ reverse (zip perhops routes)
  where
    nhops   = length  hops
    perhops = map fst hops                                   :: [PerHopSecrets]
    routes  = map (encodeIntoBytes . snd) hops               :: [[Word8]]
    sizes   = map length routes                              :: [SizeInBytes]

    -- add the size of the mac to the size of the route, except for the final destination
    addMacSize :: [SizeInBytes] -> [SizeInBytes]
    addMacSize []      = []
    addMacSize [final] = [final]
    addMacSize (n:ns)  = (n+16) : addMacSize ns

    finalFiller   = computeFinalFiller headerBetaSize (zip perhops $ addMacSize sizes)
    finalRoute    = last routes
    finalPad      = headerBetaSize - length finalRoute - fillerSize finalFiller
    finalBeta     = FinalBeta (replicate finalPad 0) finalFiller

    worker :: NextBeta -> [(PerHopSecrets, [Word8])] -> [SphinxHeader]
    worker next [] = [] 
    worker next ((perhop,route):rest) = header : worker next' rest where 

      ss     = fromWord256 $ hopSharedSecret perhop
      encKey = Key (mixKDF SphinxRouteEncKey ss)
      encIV  = IV  (mixKDF SphinxRouteEncIV  ss) 
      macKey = Key (mixKDF SphinxMacKey      ss)

      encrypt :: [Word8] -> [Word8]
      encrypt = mixRouteEncDec encKey encIV

      beta = case next of
        NextBeta  nextBeta nextGamma -> encrypt $ take headerBetaSize $ (route ++ nextGamma ++ nextBeta)
        FinalBeta nextBeta filler    -> encrypt (route ++ nextBeta) ++ fromFiller filler

      alpha  = hopPublicKey perhop
      gamma  = mixMAC macKey beta
      header = MkHeader alpha beta gamma
      next'  = NextBeta beta (macBytes gamma)

--------------------------------------------------------------------------------
-- * processing mix headers

processMixHeaderGeneric :: Binary route => MixNodeInt addr -> SphinxHeader -> Either String (route, SphinxHeader)
processMixHeaderGeneric mixNode (MkHeader alpha beta gamma) = 
  if gamma /= macBeta  
    then Left $ "MAC of beta doesn't match\n - header gamma = " ++ show gamma ++ "\n - MAC(beta)    = " ++ show macBeta
    else case decodeFromBytes betaTilde of
      Nothing                   -> Left  "cannot parse beginning of beta"
      Just (route, _size, rest) -> Right (route, MkHeader alpha' beta' gamma') where
        (gamma1, rest1) = splitAt 16 rest
        gamma' = MAC (W128 gamma1)
        beta'  = take betaSize rest1

  where
    shared  = diffieHellmanSharedSecret (nodePrivKey mixNode) alpha
    ss      = fromWord256 shared 
    encKey  = Key (mixKDF SphinxRouteEncKey ss)
    encIV   = IV  (mixKDF SphinxRouteEncIV  ss) 
    macKey  = Key (mixKDF SphinxMacKey      ss)

    betaSize  = length beta
    macBeta   = mixMAC macKey beta
    betaTilde = mixRouteEncDec encKey encIV (beta ++ replicate betaSize 0)  -- we don't know yet how long "route" is, so just add enough zeros lol

    blinder = computeBlinder alpha shared
    alpha'  = blindPublicKey blinder alpha

--------------------------------------------------------------------------------
-- * generate random mix nodes 

randomMixNode' :: IO addr -> IO (MixNodeInt addr)
randomMixNode' mkRndAddr = do
  (sk,pk) <- randomKeyPair
  addr    <- mkRndAddr -- randomMixAddr 16
  let nodeExt = MkMixNodeExt
       { nodePubKey  = pk
       , nodeAddress = addr
       }
  return $ MkMixNodeInt
    { nodePrivKey = sk
    , nodeExt     = nodeExt
    }

randomMixPath' :: IO addr -> NHops -> IO [MixNodeInt addr]
randomMixPath' mkRndAddr nhops = replicateM nhops (randomMixNode' mkRndAddr)

--------------------------------------------------------------------------------
-- * basic sanity check testing

newtype TmpAddr 
  = MkTmpAddr [Word8]
  deriving (Eq,Show)

randomTmpAddr :: Int -> IO TmpAddr
randomTmpAddr len = MkTmpAddr <$> replicateM len randomIO

data TestRouting 
  = A String
  | B Int
  | C Bool [Int]
  | F String
  deriving (Eq,Show,Generic)

instance Binary TestRouting

testRoute :: [TestRouting]
testRoute =
  [ A "foobar"
  , B 1137
  , C True [3,4,5]
  , A "whatever"
  , A "almafa"
  , B 777
  , F "final destination"
  ]

testProcess :: [MixNodeInt TmpAddr] -> SphinxHeader -> [TestRouting]
testProcess = go 0 where
  go idx []           _      = []
  go idx (node:nodes) header = case processMixHeaderGeneric node header of
    Left  errmsg           -> error $ "error at hop #" ++ show idx ++ ": " ++ errmsg
    Right (route,header')  -> route : go (idx+1) nodes header'

testMain :: IO ()
testMain = do
  let headerBetaSize = 250
  sk <- randomSecretKey
  let route = testRoute
  let nhops = length route
  mixpath <- randomMixPath' (randomTmpAddr 16) nhops
  let perhopsecrets = computePerHopSecrets sk (map nodeExt mixpath)

  let headers = computeAllHeadersGeneric headerBetaSize (zip perhopsecrets route)
  -- mapM_ print headers
  let header  = head headers
  print $ map (length . sphinxBeta) headers
  print $ testProcess mixpath header

--------------------------------------------------------------------------------

