
module Mix.Packet where

--------------------------------------------------------------------------------

import Data.Word
import Sphinx.Header
import Mix.Address

--------------------------------------------------------------------------------

data MixPacket = MkMixPacket
  { mixHeader  :: SphinxHeader
  , mixPayload :: ByteString
  }
  deriving (Eq)

--------------------------------------------------------------------------------
