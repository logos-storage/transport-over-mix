
-- | Do some plotting (useful especially during development)
--

{-# LANGUAGE OverloadedStrings #-}
module Simulate.Plots where

--------------------------------------------------------------------------------

import Control.Monad

import qualified Data.Text             as T
import qualified Data.Text.IO          as T
import qualified Data.Text.Encoding    as T
import qualified Data.ByteString       as B
import qualified Data.ByteString.Char8 as C

import Simulate.Distributions
import Simulate.Plots.ITerm2

import Granite.Svg 

--------------------------------------------------------------------------------

newtype SVG = SVG B.ByteString

makeSVG :: T.Text -> SVG
makeSVG text = SVG (T.encodeUtf8 text)

plotSVG :: SVG -> IO ()
plotSVG (SVG svg) = do
  let terminal = itermLegacyImage svg
  C.putStrLn terminal

--------------------------------------------------------------------------------

testPlotSVG = do
  xs <- testSamples

  let nbins = 100
  let title = T.pack $ "histogram; nbins = " ++ show nbins

  let svg = makeSVG $ histogram
        (bins nbins (-4) 4)
        xs
        (defPlot
          { widthChars  = 80
          , heightChars = 20
          , legendPos = LegendBottom
          , xFormatter = \_ _ v -> T.pack (show (round v :: Int))
          , xNumTicks = 10
          , yNumTicks = 5
          , plotTitle = title
          })

  plotSVG svg

--------------------------------------------------------------------------------

{-

-- note: terminal plotting in Granite looks very buggy on my machine

import Granite

testPlotTerminal = do
  xs <- testSamples

  let nbins = 30
  let title = T.pack $ "histogram; nbins = " ++ show nbins

  let text = histogram
        (bins nbins (-4) 4)
        xs
        (defPlot
          { widthChars  = 80
          , heightChars = 20
          , legendPos = LegendBottom
          , xFormatter = \_ _ v -> T.pack (show (round v :: Int))
          , xNumTicks = 10
          , yNumTicks = 5
          , plotTitle = title
          })

  T.putStrLn text

-}

--------------------------------------------------------------------------------

testSamples = do
  let gauss = GaussDistr 0 1
  let expo  = ExpoDistr 2
  let trunc = BiTruncExpoDistr (0.3, 5.0) expo

  xs <- sampleN trunc 10000
  putStrLn $ "mean    = " ++ show (average   xs)
  putStrLn $ "std dev = " ++ show (deviation xs)
  return xs

--------------------------------------------------------------------------------
