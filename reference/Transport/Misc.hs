
module Transport.Misc where

--------------------------------------------------------------------------------

import Data.Word

import qualified Data.ByteString      as B
import qualified Data.ByteString.Lazy as L

import qualified Data.Set as Set

--------------------------------------------------------------------------------
-- * alternative Show instance for ByteString

showByteString :: B.ByteString -> String
showByteString b = "<<bytestring of size " ++ show (B.length b) ++ ">>"

showLazyByteString :: L.ByteString -> String
showLazyByteString lb = "<<lazy bytestring of size " ++ show (L.length lb) ++ ">>"

--------------------------------------------------------------------------------

nubOrd :: (Eq a, Ord a) => [a] -> [a]
nubOrd = Set.toList . Set.fromList

--------------------------------------------------------------------------------
