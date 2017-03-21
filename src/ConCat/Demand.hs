{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE TypeOperators, GADTs, KindSignatures #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE FlexibleInstances, FlexibleContexts, UndecidableInstances, MultiParamTypeClasses #-} -- for Functor instance
{-# OPTIONS_GHC -Wall #-}

{-# OPTIONS_GHC -fno-warn-unused-imports #-} -- TEMP
-- {-# OPTIONS_GHC -fno-warn-unused-binds   #-} -- TEMP

----------------------------------------------------------------------
-- |
-- Module      :  ConCat.Demand
-- 
-- Maintainer  :  conal@conal.net
-- Stability   :  experimental
-- 
-- Demand algebra
----------------------------------------------------------------------

module ConCat.Demand {- (Demand(..),demand,(:-?)(..)) -} where

import Prelude hiding (id,(.),curry,uncurry,const)
import qualified Prelude as P

import Control.Applicative (liftA2)

import Control.Newtype (Newtype(..))

import ConCat.Misc ((:*),(:+),Unop,inNew,inNew2)
import ConCat.Category

-- | Demand pattern
data Demand :: * -> * where
  NoneD  :: Demand a
  (:***) :: Demand a -> Demand b -> Demand (a :* b)
  (:+++) :: Demand a -> Demand b -> Demand (a :+ b)
  (:~>)  :: Demand a -> Demand b -> Demand (a -> b)
  AllD   :: Demand a

deriving instance Show (Demand a)

{--------------------------------------------------------------------
    Semantics
--------------------------------------------------------------------}

-- | Semantic function. Extract just the demanded information.
demand :: Demand a -> Unop a
demand NoneD        = nothing
demand (ra :*** rb) = demand ra *** demand rb
demand (ra :+++ rb) = demand ra +++ demand rb
demand (ra :~>  rb) = demand ra ~>  demand rb
demand AllD         = id

nothing :: Unop a
nothing = P.const (error "empty demand pulled")

-- I'm uneasy about handling of functions. Does demand ra need to be inverted?

-- | Alternative Semantic function. Splits into needed info and complement.
split :: Demand a -> (Unop a,Unop a)
split NoneD        = (nothing,id)
split (ra :*** rb) = lift2Split (***) ra rb
split (ra :+++ rb) = lift2Split (+++) ra rb
split (ra :~>  rb) = lift2Split (~>)  ra rb
split AllD         = (id,nothing)

-- Alternative definition
_split :: Demand a -> (Unop a,Unop a)
_split = demand &&& demand . complementD

lift2Split :: (Unop a -> Unop b -> c) -> Demand a -> Demand b -> (c, c)
lift2Split (@@) ra rb = (pa @@ pb, qa @@ qb)
  where
    (pa,qa) = split ra
    (pb,qb) = split rb

-- | Complement of Demand
complementD :: Unop (Demand a)
complementD NoneD        = AllD
complementD (ra :*** rb) = complementD ra *: complementD rb
complementD (ra :+++ rb) = complementD ra +: complementD rb
complementD (ra :~> rb)  = complementD ra >: complementD rb
complementD AllD         = NoneD

{--------------------------------------------------------------------
    Smart constructors
--------------------------------------------------------------------}

-- | Product demand
(*:) :: Demand a -> Demand b -> Demand (a :* b)
(*:) = combineD (:***)

-- | Sum demand
(+:) :: Demand a -> Demand b -> Demand (a :+ b)
(+:) = combineD (:+++)

-- | Function demand
(>:) :: Demand a -> Demand b -> Demand (a -> b)
(>:) = combineD (:~>)

-- | Building block for smart constructor, assuming that @NoneD `op` NoneD ==
-- NoneD@ and @AllD `op` AllD == AllD@.
combineD :: Unop (Demand a -> Demand b -> Demand (a `op` b))
combineD  _   NoneD NoneD = NoneD
combineD  _   AllD  AllD  = AllD
combineD (@@) ra    rb    = ra @@ rb

{--------------------------------------------------------------------
    Construction & destruction
--------------------------------------------------------------------}

pairD :: (Demand a :* Demand b) -> Demand (a :* b)
pairD = uncurry (*:)

unpairD :: Demand (a :* b) -> (Demand a :* Demand b)
unpairD NoneD        = (NoneD,NoneD)
unpairD (ra :*** rb) = (ra   ,rb   )
unpairD AllD         = (AllD ,AllD )

inUnpairD :: (Demand a' :* Demand b' -> Demand a :* Demand b)
          -> (a :* b :+? a' :* b')
inUnpairD = unpairD ~> pairD


plusD :: (Demand a, Demand b) -> Demand (a :+ b)
plusD = uncurry (+:)

unplusD :: Demand (a :+ b) -> (Demand a , Demand b)
unplusD NoneD        = (NoneD, NoneD)
unplusD (ra :+++ rb) = (ra   , rb   )
unplusD AllD         = (AllD , AllD )

funD :: (Demand a, Demand b) -> Demand (a -> b)
funD = uncurry (>:)

unfunD :: Demand (a -> b) -> (Demand a, Demand b)
unfunD NoneD       = (NoneD,NoneD)
unfunD (ra :~> rb) = (ra, rb)
unfunD AllD        = (AllD,AllD)

inUnfunD :: ((Demand a, Demand b) -> (Demand a', Demand b'))
         -> (Demand (a -> b) -> Demand (a' -> b'))
inUnfunD = unfunD ~> funD

mergeD :: a :+? a :* a
mergeD = uncurry lubD . unpairD

-- mergeD NoneD        = NoneD
-- mergeD (ra :*** rb) = ra `lubD` rb
-- mergeD AllD         = AllD

{--------------------------------------------------------------------
    Lattice
--------------------------------------------------------------------}

-- Demands form a lattice with bottom = NoneD, top = AllD, and lub & glb as
-- follows. The semantic function preserves lattice structure (is a lattice
-- morphism).

-- | Least upper bound on demands. Specification: 
-- @demand (ra `lubD` rb) == demand ra `lub` demand rb@.
lubD :: Demand a -> Demand a -> Demand a
NoneD      `lubD` a            = a
a          `lubD` NoneD        = a
AllD       `lubD` _            = AllD
_          `lubD` AllD         = AllD
(a :*** b) `lubD` (a' :*** b') = (a `lubD` a') *: (b `lubD` b')
(a :+++ b) `lubD` (a' :+++ b') = (a `lubD` a') +: (b `lubD` b')
(a :~> b)  `lubD` (a' :~> b')  = (a `lubD` a') >: (b `lubD` b')

-- | Greatest lower bound on demands. Specification: 
-- @demand (ra `glbD` rb) == demand ra `glb` demand rb@.
glbD :: Demand a -> Demand a -> Demand a
NoneD      `glbD` _            = NoneD
_          `glbD` NoneD        = NoneD
AllD       `glbD` b            = b
a          `glbD` AllD         = a
(a :*** b) `glbD` (a' :*** b') = (a `glbD` a') *: (b `glbD` b')
(a :+++ b) `glbD` (a' :+++ b') = (a `glbD` a') +: (b `glbD` b')
(a :~> b)  `glbD` (a' :~> b')  = (a `glbD` a') >: (b `glbD` b')

-- The catch-all cases in lubD and glbD are sum/product.
-- Impossible, but GHC doesn't realize. :(

{--------------------------------------------------------------------
    Demand flow arrow
--------------------------------------------------------------------}

infixr 1 :-?, :+?

-- | Map consumer demand to producer demand
type a :+? b = Demand b -> Demand a

-- | Arrow of demand flow, running counter to value flow
newtype a :-? b = RX { unRX :: a :+? b }

instance Newtype (a :-? b) where
  type O (a :-? b) = a :+? b
  pack = RX
  unpack (RX f) = f

instance Category (:-?) where
  id  = pack id
  (.) = inNew2 (flip (.))                -- note flow reversal

instance ProductCat (:-?) where
  exl = pack (*: NoneD)
  exr = pack (NoneD *:)
  dup = pack mergeD
  (***) = inNew2 $ \ f g -> inUnpairD (f *** g)

instance CoproductCat (:-?) where
  inl = pack (exl . unplusD)
  inr = pack (exr . unplusD)
  -- jam = pack (plusD . dup)
  (|||) = (inNew2.liftA2) (+:)

instance ConstCat (:-?) a where
  const _ = pack (const NoneD)

-- instance ClosedCat (:-?) where
  -- uncurry = pack (funD . first pairD . lassocP . second unfunD . unfunD)
  -- uncurry = RX $ funD . second funD . rassocP . first unpairD . unfunD

foo1 :: (a :* b -> c) :+? (a -> b -> c)
foo1 d = funD (first pairD (lassocP (second unfunD (unfunD d))))

foo2 :: (a :* b -> c) :+? (a -> b -> c)
foo2 = funD . first pairD . lassocP . second unfunD . unfunD

foo3 :: (a :* b -> c) :-? (a -> b -> c)
foo3 = pack (funD . first pairD . lassocP . second unfunD . unfunD)

#if 0

apply' :: (a -> b) :* a :+? b
       :: Demand b -> Demand ((a -> b) :* a)

curry' :: (a :* b -> c) :+? (a -> b -> c)
       :: Demand (a -> b -> c) :+? Demand (a :* b -> c)

d :: Demand (a -> b -> c)
unfunD d :: Demand a :* Demand (b -> c)
second unfunD (unfunD d) :: Demand a :* (Demand b :* Demand c)
lassocP (second unfunD (unfunD d)) :: (Demand a :* Demand b) :* Demand c
first pairD (lassocP (second unfunD (unfunD d))) :: Demand (a :* b) :* Demand c
funD (first pairD (lassocP (second unfunD (unfunD d)))) :: Demand (a :* b -> c)

-- Nope!

curry' :: (a :* b :+? c) -> (a :+? (b -> c))

f :: a :* b :+? c
  :: Demand c -> Demand (a :* b)
unpairD . f :: Demand c -> Demand a :* Demand b


need :: a :+? (b -> c)
     :: Demand (b -> c) -> Demand a

#endif