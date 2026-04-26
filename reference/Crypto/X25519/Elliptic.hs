
-- | The cyclic subgroup of Curve25519
--
-- Curve25519 is the Montgomery curve defined by
--
-- > y^2 = x^3 + 486662*x^2 + x
--
-- over the prime field @p = 2^255 - 19@
--
-- See <https://cr.yp.to/ecdh/curve25519-20060209.pdf>
--
-- Note: In the @X = x/z@ representation, we can do efficient doubling and 
-- efficient scalar multiplication, but not clear how to do addition.
--
-- But we are only using X25519 (Diffie-Hellman), no signatures
--

{-# LANGUAGE Strict #-}
module Crypto.X25519.Elliptic where

--------------------------------------------------------------------------------

import Data.Bits

import Crypto.X25519.BaseField
import Crypto.X25519.ScalarField

--------------------------------------------------------------------------------

constA, constA' :: Fp
constA  = Fp 486662
constA' = Fp 121665         -- (A-2) / 4

-- | We only store the @x@ coordinate, with @z=1@ being implicit
newtype G 
  = Gx Fp
  deriving (Eq,Show)

xcoordAsInteger :: G -> Integer
xcoordAsInteger (Gx x) = fromFp x

-- | We store both the @x@ and $z$ coordinates
data G'
  = Gxz !Fp !Fp
  deriving (Eq,Show)

toProj :: G -> G'
toProj (Gx x) = Gxz x 1

fromProj :: G' -> G
fromProj (Gxz x z) = Gx (x/z)

basePoint :: G
basePoint = Gx 9

basePoint' :: G'
basePoint' = Gxz 9 1

inf :: G'
inf = Gxz 1 0

--------------------------------------------------------------------------------

affDouble :: G -> G
affDouble = fromProj . projDouble . toProj

--------------------------------------------------------------------------------

projDouble :: G' -> G'
projDouble (Gxz x z) = Gxz x2 z2 where
  u = (x-z) * (x-z)
  v = (x+z) * (x+z)
  x2 = u * v
  m2 = v - u
  z2 = m2 * (v + constA' * m2)

-- | Given Q, Q' and Q-Q' (assuming not 0 or inf), we compute Q+Q'
projLadderStep :: G' -> G' -> G -> G'
projLadderStep (Gxz x z ) (Gxz x' z') (Gx x1) = Gxz x3 z3 where
   u = (x - z) * (x' + z')
   v = (x + z) * (x' - z')
   x3 = (u + v) * (u + v)  -- * z1 = 1
   z3 = (u - v) * (u - v) * x1

--------------------------------------------------------------------------------

(**) :: Fq -> G -> G
(**) expo base = scalarMul (fromFq expo) base

scalarMul :: Integer -> G -> G
scalarMul expo base = fromProj $ montgomeryLadder expo base

montgomeryLadder :: Integer -> G -> G' 
montgomeryLadder expo base = fst (go expo) where
  -- returns (n*base, (n+1)*base) 
  go :: Integer -> (G', G')
  go 0 = (inf , toProj base)
  go n = case n .&. 1 of
    0 -> (projDouble a   , ladderStep a b)    -- 2k   = 2*k       ; 2k+1 = k + (k+1)
    1 -> (ladderStep a b , projDouble b  )    -- 2k+1 = k + (k+1) ; 2k+2 = 2*(k+1)
    where 
      (a,b) = go (shiftR n 1)

  ladderStep a b = projLadderStep a b base

--------------------------------------------------------------------------------

sanityCheck :: Bool
sanityCheck = (scalarMul priv basePoint == pub) where
  priv =    34637982121745647379369242364578736860238507147912635042240559108083448531832
  pub  = Gx 24771927253352877576321681419849838916408500873060548523943816650212634100610

{- 
-- test case:
priv = 34637982121745647379369242364578736860238507147912635042240559108083448531832
pub  = 24771927253352877576321681419849838916408500873060548523943816650212634100610
-}

--------------------------------------------------------------------------------
