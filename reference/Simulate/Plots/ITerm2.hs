
-- | The macOS terminal emulator @iTerm2@ allows graphical plots in the terminal

module Simulate.Plots.ITerm2 where

--------------------------------------------------------------------------------

import Data.Word

import qualified Data.ByteString       as B
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString.Lazy  as LB

import Data.Base64.Types
import Data.ByteString.Base64

--------------------------------------------------------------------------------
-- * push images to the terminal

showImage :: B.ByteString -> IO ()
showImage img = C.putStrLn (itermImage img)

showLegacyImage :: B.ByteString -> IO ()
showLegacyImage img = C.putStrLn (itermLegacyImage img)

--------------------------------------------------------------------------------
-- * legacy image support

itermImage :: B.ByteString -> B.ByteString
itermImage image = undefined

--
-- apparently, the syntax is: 
--
-- > prefix;<metakey>=<key1>=<value1>;<key2>=<value2>;...<keyN>=<valueN>:<base64data>^G
--
-- (WTF) 
--
itermLegacyImage :: B.ByteString -> B.ByteString
itermLegacyImage image = final where
  final  = B.concat
    [ itermPrefix
    , C.pack "File=inline=1;width=70%"
    , B.singleton colon
    , toBase64 image
    , B.singleton ctrl_g
    ]

toBase64 :: B.ByteString -> B.ByteString
toBase64 what = extractBase64 (encodeBase64' what) 

--------------------------------------------------------------------------------
-- * low-level iIterm command interface

itermCmdLowLevel :: String -> B.ByteString -> B.ByteString
itermCmdLowLevel key value = B.concat
  [ itermPrefix
  , C.pack key
  , B.singleton equals
  , value
  , B.singleton ctrl_g
  ]

itermPrefix :: B.ByteString
itermPrefix = B.pack (esc : rightBracket : 49 : 51 : 51 : 55 : semicolon : [])
-- ... ^^^^                              "  1    3    3    7 "

--------------------------------------------------------------------------------
-- * terminal codes

esc, rightBracket, ctrl_g, semicolon, equals :: Word8 
esc          = 27
leftBracket  = 91
rightBracket = 93
ctrl_g       = 7
colon        = 58
semicolon    = 59
equals       = 61

--------------------------------------------------------------------------------
