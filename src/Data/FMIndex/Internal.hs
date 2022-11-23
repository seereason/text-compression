{-# LANGUAGE MultiWayIf       #-}
{-# LANGUAGE ViewPatterns     #-}
{-# LANGUAGE Strict           #-}
{-# LANGUAGE DeriveGeneric    #-}
{-# LANGUAGE TypeApplications #-}


-- |
-- Module      :  Data.FMIndex.Internal
-- Copyright   :  (c) Matthew Mosior 2022
-- License     :  BSD-style
-- Maintainer  :  mattm.github@gmail.com
-- Portability :  portable
--
-- = WARNING
--
-- This module is considered __internal__.
--
-- The Package Versioning Policy __does not apply__.
--
-- The contents of this module may change __in any way whatsoever__
-- and __without any warning__ between minor versions of this package.
--
-- Authors importing this library are expected to track development
-- closely.
--
-- All credit goes to the author(s)/maintainer(s) of the
-- [containers](https://hackage.haskell.org/package/containers) library
-- for the above warning text.
--
-- = Description
--
-- Various data structures and custom data types to describe the
-- [Full-text Minute-space index (FM-index)](https://en.wikipedia.org/wiki/FM-index)
-- and the Inverse FM-index implementations, namely 'seqToOccCKB', 'seqToOccCKT', 'seqToCcB', 'seqToCcT', 'seqFromFMIndexB', and 'seqFromFMIndexT'.
--
-- The FM-index implementations rely heavily upon 'Seq' provided by the [containers](https://hackage.haskell.org/package/containers),
-- 'STRef' and associated functions in the [stref](https://hackage.haskell.org/package/base-4.17.0.0/docs/Data-STRef.html) library,
-- and 'runST' in the [Control.Monad.ST](https://hackage.haskell.org/package/base-4.17.0.0/docs/Control-Monad-ST.html) library.
--
-- = Example FM-index Output
--
-- The below example is taken from [this](https://en.wikipedia.org/wiki/FM-index) wikipedia page.
--
-- Given the following input, "abracadabra":
--
-- and
--
-- Given the following Burrows-Wheeler matrix (BWM) of the input "abracadabra":
--
-- +----+---+---------------------------------------+---+
-- | I  | F |                                       | L |
-- +====+===+===+===+===+===+===+===+===+===+===+===+===+
-- | 1  | $ | a | b | r | a | c | a | d | a | b | r | a |
-- +----+---+---+---+---+---+---+---+---+---+---+---+---+
-- | 2  | a | $ | a | b | r | a | c | a | d | a | b | r |
-- +----+---+---+---+---+---+---+---+---+---+---+---+---+
-- | 3  | a | b | r | a | $ | a | b | r | a | c | a | d |
-- +----+---+---+---+---+---+---+---+---+---+---+---+---+
-- | 4  | a | b | r | a | c | a | d | a | b | r | a | $ |
-- +----+---+---+---+---+---+---+---+---+---+---+---+---+
-- | 5  | a | c | a | d | a | b | r | a | $ | a | b | r |
-- +----+---+---+---+---+---+---+---+---+---+---+---+---+
-- | 6  | a | d | a | b | r | a | $ | a | b | r | a | c |
-- +----+---+---+---+---+---+---+---+---+---+---+---+---+
-- | 7  | b | r | a | $ | a | b | r | a | c | a | d | a |
-- +----+---+---+---+---+---+---+---+---+---+---+---+---+
-- | 8  | b | r | a | c | a | d | a | b | r | a | $ | a |
-- +----+---+---+---+---+---+---+---+---+---+---+---+---+
-- | 9  | c | a | d | a | b | r | a | $ | a | b | r | a |
-- +----+---+---+---+---+---+---+---+---+---+---+---+---+
-- | 10 | d | a | b | r | a | $ | a | b | r | a | c | a |
-- +----+---+---+---+---+---+---+---+---+---+---+---+---+
-- | 11 | r | a | $ | a | b | r | a | c | a | d | a | b |
-- +----+---+---+---+---+---+---+---+---+---+---+---+---+
-- | 12 | r | a | c | a | d | a | b | r | a | $ | a | b |
-- +----+---+---+---+---+---+---+---+---+---+---+---+---+
--
-- The FM-index output of the Burrows-Wheeler transform of the input is:
--
-- C[c] of "ard$rcaaaabb"
--
-- +------+---+---+---+---+---+----+
-- | c    | $ | a | b | c | d | r  |
-- +------+---+---+---+---+---+----+
-- | C[c] | 0 | 1 | 6 | 8 | 9 | 10 |
-- +------+---+---+---+---+---+----+
--
-- and
--
-- Occ(c,k) of "ard$rcaaaabb"
--
-- +---+---+---+---+---+---+---+---+---+---+----+----+----+
-- |   | a | r | d | $ | r | c | a | a | a | a  | b  | b  |
-- +---+---+---+---+---+---+---+---+---+---+----+----+----+
-- |   | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
-- +===+===+===+===+===+===+===+===+===+===+====+====+====+
-- | $ | 0 | 0 | 0 | 1 | 1 | 1 | 1 | 1 | 1 | 1  | 1  | 1  |
-- +---+---+---+---+---+---+---+---+---+---+----+----+----+
-- | a | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 3 | 4 | 5  | 5  | 5  |
-- +---+---+---+---+---+---+---+---+---+---+----+----+----+
-- | b | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0  | 1  | 2  |
-- +---+---+---+---+---+---+---+---+---+---+----+----+----+
-- | c | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 1 | 1 | 1  | 1  | 1  |
-- +---+---+---+---+---+---+---+---+---+---+----+----+----+
-- | d | 0 | 0 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1  | 1  | 1  |
-- +---+---+---+---+---+---+---+---+---+---+----+----+----+
-- | r | 0 | 1 | 1 | 1 | 2 | 2 | 2 | 2 | 2 | 2  | 2  | 2  |
-- +---+---+---+---+---+---+---+---+---+---+----+----+----+


module Data.FMIndex.Internal where

import Data.BWT.Internal()
import Data.MTF.Internal

import Control.Monad as CM
import Control.Monad.ST as CMST
import Control.Monad.State.Strict()
import Data.ByteString as BS
import Data.ByteString.Char8()
import Data.ByteString.Internal()
import Data.Foldable()
import Data.List()
import Data.Maybe()
import Data.Sequence as DS (Seq(..),ViewR(..),empty,(|>))
import Data.Sequence.Internal as DSI
import Data.STRef as DSTR
import Data.Text as DText
import GHC.Generics (Generic)
import Prelude as P


{-Base level types.-}

-- | Basic FMIndex ('ByteString') data type.
newtype FMIndexB = FMIndexB (CcB,OccCKB)
  deriving (Eq,Ord,Show,Read,Generic)

-- | Basic FMIndex ('Text') data type.
newtype FMIndexT = FMIndexT (CcT,OccCKT)
  deriving (Eq,Ord,Show,Read,Generic)

-- | Basic OccCKB ('ByteString') data type.
newtype OccCKB = OccCKB (Seq (Maybe ByteString,Seq (Int,Int,Maybe ByteString)))
  deriving (Eq,Ord,Show,Read,Generic)

-- | Basic OccCKT ('Text') data type.
newtype OccCKT = OccCKT (Seq (Maybe Text,Seq (Int,Int,Maybe Text)))
  deriving (Eq,Ord,Show,Read,Generic)

-- | Basic C[c] table ('ByteString') data type.
newtype CcB = CcB (Seq (Int,Maybe ByteString))
  deriving (Eq,Ord,Show,Read,Generic)

-- | Basic C[c] table ('Text') data type.
newtype CcT = CcT (Seq (Int,Maybe Text))
  deriving (Eq,Ord,Show,Read,Generic)

{-------------------}


{-toOccCK (ByteString) functions.-}

-- | Abstract 'PBOccCKSeqB' type utilizing a 'Seq'.
type PBOccCKSeqB = Seq (Maybe ByteString)

-- | Abstract 'OccCKSeqB' type utilizing a 'Seq'.
-- (c,(indexofinputcurrentelement,Occ(c,k),inputcurrentelement))
type OccCKSeqB = Seq (Maybe ByteString,Seq (Int,Int,Maybe ByteString))

-- | Abstract data type representing a 'OccCKSeqB' in the (strict) ST monad.
type STOccCKSeqB s a = STRef s OccCKSeqB

-- | State function to update 'OccCKSeqB'
-- with each step of the OccCK.
updateSTOccCKSeqAB :: STOccCKSeqB s (Seq (Maybe ByteString,Seq (Int,Int,Maybe ByteString)))
                   -> (Int,Int,Maybe ByteString)
                   -> ST s ()
updateSTOccCKSeqAB s e = do
  s2 <- readSTRef s
  case viewr s2 of
    EmptyR           -> pure ()
    (s2h DS.:> s2fm) -> writeSTRef s (s2h DS.|> (((\(a,_) -> a) s2fm),((\(_,b) -> b) s2fm) DS.|> e))

-- | State function to update 'OccCKSeqB'
-- with each step of the OccCK.
updateSTOccCKSeqBB :: STOccCKSeqB s (Seq (Maybe ByteString,Seq (Int,Int,Maybe ByteString)))
                   -> Maybe ByteString
                   -> ST s ()
updateSTOccCKSeqBB s e = do
  s2 <- readSTRef s
  writeSTRef s (s2 DS.|> (e,DS.empty))

-- | State function to create empty 'STOccCKSeqB' type.
emptySTOccCKSeqB :: ST s (STOccCKSeqB s a)
emptySTOccCKSeqB = newSTRef DS.empty

-- | Abstract 'STOccCKILB' and associated state type.
type STOccCKILB s a = STRef s (Seq (Maybe ByteString))

-- | State function to load list into 'STOccCKILB'.
loadSTOccCKILB :: STOccCKILB s (Maybe ByteString)
               -> Seq (Maybe ByteString)
               -> ST s ()
loadSTOccCKILB s e = writeSTRef s e

-- | State function to create empty 'STOccCKILB' type.
emptySTOccCKILB :: ST s (STOccCKILB s a)
emptySTOccCKILB = newSTRef DS.empty

-- | Abstract 'STOccCKCounterB' and associated state type.
type STOccCKCounterB s a = STRef s Int

-- | State function to update 'STOccCKCounterB'.
updateSTOccCKCounterB :: STOccCKCounterB s Int
                        -> Int
                        -> ST s ()
updateSTOccCKCounterB s e = writeSTRef s e

-- | State function to create empty 'STOccCKCounterB' type.
emptySTOccCKCounterB :: ST s (STOccCKCounterB s Int)
emptySTOccCKCounterB = newSTRef 0 

-- | Strict state monad function.
seqToOccCKB :: PBOccCKSeqB
            -> ST s OccCKSeqB
seqToOccCKB DS.Empty      = do
  boccckseqstackempty  <- emptySTOccCKSeqB
  boccckseqstackemptyr <- readSTRef boccckseqstackempty
  return boccckseqstackemptyr
seqToOccCKB xs            = do
  boccckseqstack     <- emptySTOccCKSeqB 
  boccckinitiallist  <- emptySTOccCKILB
  boccckcounterstack <- emptySTOccCKCounterB
  let il = nubSeq' xs
  loadSTOccCKILB boccckinitiallist
                 il
  cboccckinitiallist <- readSTRef boccckinitiallist
  iOccCKB cboccckinitiallist
          xs
          boccckseqstack
          boccckcounterstack
  boccckseqstackr <- readSTRef boccckseqstack
  return boccckseqstackr
    where
      iOccCKB DS.Empty      _      _        _        = pure ()
      iOccCKB (y DS.:<| ys) zs     boccckss boccckcs = do
        boccckis <- emptySTOccCKCounterB
        updateSTOccCKCounterB boccckis
                              1
        updateSTOccCKSeqBB boccckss
                           y
        iiOccCKB y
                 zs
                 boccckss
                 boccckis
                 boccckcs                           
        iOccCKB ys
                zs
                boccckss
                boccckcs
      iiOccCKB _  DS.Empty      _        _        boccckcs = do
        updateSTOccCKCounterB boccckcs
                              0
        pure ()
      iiOccCKB as (b DS.:<| bs) boccckss boccckis boccckcs = do
        cboccckis <- readSTRef boccckis
        cboccckcs <- readSTRef boccckcs
        if | as == b
           -> do updateSTOccCKSeqAB boccckss
                                    (cboccckis,cboccckcs + 1,b)
                 updateSTOccCKCounterB boccckcs
                                       (cboccckcs + 1)
                 updateSTOccCKCounterB boccckis
                                       (cboccckis + 1)
                 iiOccCKB as
                          bs
                          boccckss
                          boccckis
                          boccckcs    
           | otherwise
           -> do updateSTOccCKSeqAB boccckss
                                    (cboccckis,cboccckcs,b)
                 updateSTOccCKCounterB boccckis
                                       (cboccckis + 1)
                 iiOccCKB as
                          bs
                          boccckss
                          boccckis
                          boccckcs

{---------------------------------}


{-toOccCK (Text) functions.-}

-- | Abstract 'PTOccCKSeqT' type utilizing a 'Seq'.
type PTOccCKSeqT = Seq (Maybe Text)

-- | Abstract 'OccCKSeqT' type utilizing a 'Seq'.
-- (c,(indexofinputcurrentelement,Occ(c,k),inputcurrentelement))
type OccCKSeqT = Seq (Maybe Text,Seq (Int,Int,Maybe Text))

-- | Abstract data type representing a 'OccCKSeqT' in the (strict) ST monad.
type STOccCKSeqT s a = STRef s OccCKSeqT

-- | State function to update 'OccCKSeqT'
-- with each step of the OccCK.
updateSTOccCKSeqAT :: STOccCKSeqT s (Seq (Maybe Text,Seq (Int,Int,Maybe Text)))
                   -> (Int,Int,Maybe Text)
                   -> ST s ()
updateSTOccCKSeqAT s e = do
  s2 <- readSTRef s
  case viewr s2 of
    EmptyR           -> pure ()
    (s2h DS.:> s2fm) -> writeSTRef s (s2h DS.|> (((\(a,_) -> a) s2fm),((\(_,b) -> b) s2fm) DS.|> e))

-- | State function to update 'OccCKSeqT'
-- with each step of the OccCK.
updateSTOccCKSeqBT :: STOccCKSeqT s (Seq (Maybe Text,Seq (Int,Int,Maybe Text)))
                   -> Maybe Text
                   -> ST s ()
updateSTOccCKSeqBT s e = do
  s2 <- readSTRef s
  writeSTRef s (s2 DS.|> (e,DS.empty))

-- | State function to create empty 'STOccCKSeqT' type.
emptySTOccCKSeqT :: ST s (STOccCKSeqT s a)
emptySTOccCKSeqT = newSTRef DS.empty

-- | Abstract 'STOccCKILT' and associated state type.
type STOccCKILT s a = STRef s (Seq (Maybe Text))

-- | State function to load list into 'STOccCKILT'.
loadSTOccCKILT :: STOccCKILT s (Maybe Text)
               -> Seq (Maybe Text)
               -> ST s ()
loadSTOccCKILT s e = writeSTRef s e

-- | State function to create empty 'STOccCKILT' type.
emptySTOccCKILT :: ST s (STOccCKILT s a)
emptySTOccCKILT = newSTRef DS.empty

-- | Abstract 'STOccCKCounterT' and associated state type.
type STOccCKCounterT s a = STRef s Int

-- | State function to update 'STOccCKCounterT'.
updateSTOccCKCounterT :: STOccCKCounterT s Int
                      -> Int
                      -> ST s ()
updateSTOccCKCounterT s e = writeSTRef s e

-- | State function to create empty 'STOccCKCounterT' type.
emptySTOccCKCounterT :: ST s (STOccCKCounterT s Int)
emptySTOccCKCounterT = newSTRef 0

-- | Strict state monad function.
seqToOccCKT :: PTOccCKSeqT
            -> ST s OccCKSeqT
seqToOccCKT DS.Empty      = do
  toccckseqstackempty  <- emptySTOccCKSeqT
  toccckseqstackemptyr <- readSTRef toccckseqstackempty
  return toccckseqstackemptyr
seqToOccCKT xs            = do
  toccckseqstack     <- emptySTOccCKSeqT
  toccckinitiallist  <- emptySTOccCKILT
  toccckcounterstack <- emptySTOccCKCounterT
  let il = nubSeq' xs
  loadSTOccCKILT toccckinitiallist
                 il
  ctoccckinitiallist <- readSTRef toccckinitiallist
  iOccCKT ctoccckinitiallist
          xs
          toccckseqstack
          toccckcounterstack
  toccckseqstackr <- readSTRef toccckseqstack
  return toccckseqstackr
    where
      iOccCKT DS.Empty      _      _        _        = pure ()
      iOccCKT (y DS.:<| ys) zs     toccckss toccckcs = do
        toccckis <- emptySTOccCKCounterT
        updateSTOccCKCounterT toccckis
                              1
        updateSTOccCKSeqBT toccckss
                           y
        iiOccCKT y
                 zs
                 toccckss
                 toccckis
                 toccckcs
        iOccCKT ys
                zs
                toccckss
                toccckcs
      iiOccCKT _  DS.Empty      _        _        toccckcs = do
        updateSTOccCKCounterT toccckcs
                              0
        pure ()
      iiOccCKT as (b DS.:<| bs) toccckss toccckis toccckcs = do
        ctoccckis <- readSTRef toccckis
        ctoccckcs <- readSTRef toccckcs
        if | as == b
           -> do updateSTOccCKSeqAT toccckss
                                    (ctoccckis,ctoccckcs + 1,b)
                 updateSTOccCKCounterT toccckcs
                                       (ctoccckcs + 1)
                 updateSTOccCKCounterT toccckis
                                       (ctoccckis + 1)
                 iiOccCKT as
                          bs
                          toccckss
                          toccckis
                          toccckcs
           | otherwise
           -> do updateSTOccCKSeqAT toccckss
                                    (ctoccckis,ctoccckcs,b)
                 updateSTOccCKCounterT toccckis
                                       (ctoccckis + 1)
                 iiOccCKT as
                          bs
                          toccckss
                          toccckis
                          toccckcs

{---------------------------}


{-To Cc (ByteString) functions.-}

-- | Abstract 'PBCcSeqB' type utilizing a 'Seq'.
type PBCcSeqB = Seq (Maybe ByteString)

-- | Abstract 'CcSeqB' type utilizing a 'Seq'.
-- (C[c],c)
type CcSeqB = Seq (Int,Maybe ByteString)

-- | Abstract data type representing a 'CcSeqB' in the (strict) ST monad.
type STCcSeqB s a = STRef s CcSeqB

-- | State function to update 'CcSeqB'
-- with each step of the C[c].
updateSTCcSeqB :: STCcSeqB s (Seq (Int,Maybe ByteString))
               -> (Int,Maybe ByteString)
               -> ST s ()
updateSTCcSeqB s e = do
  s2 <- readSTRef s
  writeSTRef s (s2 DS.|> e)

-- | State function to create empty 'STCcSeqT' type.
emptySTCcSeqB :: ST s (STCcSeqB s a)
emptySTCcSeqB = newSTRef DS.empty

-- | Abstract 'STCcILB' and associated state type.
type STCcILB s a = STRef s (Seq (Maybe ByteString))

-- | State function to load list into 'STCcILB'.
loadSTCcILB :: STCcILB s (Maybe ByteString)
            -> Seq (Maybe ByteString)
            -> ST s ()
loadSTCcILB s e = writeSTRef s e

-- | State function to create empty 'STCcILB' type.
emptySTCcILB :: ST s (STCcILB s a)
emptySTCcILB = newSTRef DS.empty

-- | Abstract 'STCcCounterB' and associated state type.
type STCcCounterB s a = STRef s Int

-- | State function to update 'STCcCounterB'.
updateSTCcCounterB :: STCcCounterB s Int
                   -> Int
                   -> ST s ()
updateSTCcCounterB s e = writeSTRef s e

-- | State function to create empty 'STCcCounterT' type.
emptySTCcCounterB :: ST s (STCcCounterB s Int)
emptySTCcCounterB = newSTRef 0

-- | Strict state monad function.
seqToCcB :: PBCcSeqB
         -> ST s CcSeqB
seqToCcB DS.Empty      = do
  bccseqstackempty  <- emptySTCcSeqB
  bccseqstackemptyr <- readSTRef bccseqstackempty
  return bccseqstackemptyr
seqToCcB xs            = do
  bccseqstack     <- emptySTCcSeqB
  bccinitiallist  <- emptySTCcILB
  bcccounterstack <- emptySTCcCounterB
  let il = nubSeq' xs
  loadSTCcILB bccinitiallist
              il
  cbccinitiallist <- readSTRef bccinitiallist
  iCcB cbccinitiallist
       xs
       bccseqstack
       bcccounterstack
  bccseqstackr <- readSTRef bccseqstack
  return bccseqstackr
    where
      iCcB DS.Empty      _      _        _  = pure ()
      iCcB (y DS.:<| ys) zs     bccss bcccs = do
        updateSTCcCounterB bcccs
                           0
        iiCcB y
              zs
              bccss
              bcccs
        iCcB ys
             zs
             bccss
             bcccs
      iiCcB _  DS.Empty      _     _     = pure ()
      iiCcB as (b DS.:<| bs) bccss bcccs = do
        cbcccs <- readSTRef bcccs
        if | as == b
           -> updateSTCcSeqB bccss
                             (cbcccs,as) 
           | otherwise
           -> do updateSTCcCounterB bcccs
                                    (cbcccs + 1)
                 iiCcB as
                       bs
                       bccss 
                       bcccs

{-------------------------------}


{-To Cc (Text) functions.-}

-- | Abstract 'PTCcSeqT' type utilizing a 'Seq'.
type PTCcSeqT = Seq (Maybe Text)

-- | Abstract 'CcSeqT' type utilizing a 'Seq'.
-- (C[c],c)
type CcSeqT = Seq (Int,Maybe Text)

-- | Abstract data type representing a 'CcSeqT' in the (strict) ST monad.
type STCcSeqT s a = STRef s CcSeqT

-- | State function to update 'CcSeqT'
-- with each step of the C[c].
updateSTCcSeqT :: STCcSeqT s (Seq (Int,Maybe Text))
               -> (Int,Maybe Text)
               -> ST s ()
updateSTCcSeqT s e = do
  s2 <- readSTRef s
  writeSTRef s (s2 DS.|> e)

-- | State function to create empty 'STCcSeqT' type.
emptySTCcSeqT :: ST s (STCcSeqT s a)
emptySTCcSeqT = newSTRef DS.empty

-- | Abstract 'STCcILT' and associated state type.
type STCcILT s a = STRef s (Seq (Maybe Text))

-- | State function to load list into 'STCcILT'.
loadSTCcILT :: STCcILT s (Maybe Text)
            -> Seq (Maybe Text)
            -> ST s ()
loadSTCcILT s e = writeSTRef s e

-- | State function to create empty 'STCcILT' type.
emptySTCcILT :: ST s (STCcILT s a)
emptySTCcILT = newSTRef DS.empty

-- | Abstract 'STCcCounterT' and associated state type.
type STCcCounterT s a = STRef s Int

-- | State function to update 'STCcCounterT'.
updateSTCcCounterT :: STCcCounterT s Int
                   -> Int
                   -> ST s ()
updateSTCcCounterT s e = writeSTRef s e

-- | State function to create empty 'STCcCounterT' type.
emptySTCcCounterT :: ST s (STCcCounterT s Int)
emptySTCcCounterT = newSTRef 0

-- | Strict state monad function.
seqToCcT :: PTCcSeqT
         -> ST s CcSeqT
seqToCcT DS.Empty      = do
  tccseqstackempty  <- emptySTCcSeqT
  tccseqstackemptyr <- readSTRef tccseqstackempty
  return tccseqstackemptyr
seqToCcT xs            = do
  tccseqstack     <- emptySTCcSeqT
  tccinitiallist  <- emptySTCcILT
  tcccounterstack <- emptySTCcCounterT
  let il = nubSeq' xs
  loadSTCcILT tccinitiallist
              il
  ctccinitiallist <- readSTRef tccinitiallist
  iCcT ctccinitiallist
       xs
       tccseqstack
       tcccounterstack
  tccseqstackr <- readSTRef tccseqstack
  return tccseqstackr
    where
      iCcT DS.Empty      _      _        _  = pure ()
      iCcT (y DS.:<| ys) zs     tccss tcccs = do
        updateSTCcCounterT tcccs
                           0
        iiCcT y
              zs
              tccss
              tcccs
        iCcT ys
             zs
             tccss
             tcccs
      iiCcT _  DS.Empty      _     _     = pure ()
      iiCcT as (b DS.:<| bs) tccss tcccs = do
        ctcccs <- readSTRef tcccs
        if | as == b
           -> updateSTCcSeqT tccss
                             (ctcccs,as)
           | otherwise
           -> do updateSTCcCounterT tcccs
                                    (ctcccs + 1)
                 iiCcT as
                       bs
                       tccss
                       tcccs

{-------------------------}


{-fromFMIndex (ByteString) functions.-}

-- | Abstract 'FFMIndexSeqB' type utilizing a 'Seq'.
type FFMIndexSeqB = Seq (Maybe ByteString)

-- | Simple Inverse FMIndex function. 
seqFromFMIndexB :: FMIndexB
                -> FFMIndexSeqB
seqFromFMIndexB (FMIndexB (CcB DS.Empty,_))    = DS.Empty
seqFromFMIndexB (FMIndexB (_,OccCKB DS.Empty)) = DS.Empty
seqFromFMIndexB xs                             = do
  let xss = (\(OccCKB b) -> b) $
            (\(_,b) -> b)      $
            (\(FMIndexB b) -> b) xs
  iFFMIndexB xss
    where
      iFFMIndexB DS.Empty         = DS.Empty 
      iFFMIndexB ((_,b) DS.:<| _) =
        fmap (\(_,_,e) -> e) b

{-------------------------------------}


{-fromFMIndex (Text) functions.-}

-- | Abstract 'FFMIndexSeqT' type utilizing a 'Seq'.
type FFMIndexSeqT = Seq (Maybe Text)

-- | Simple Inverse FMIndex function.
seqFromFMIndexT :: FMIndexT
                -> FFMIndexSeqT
seqFromFMIndexT (FMIndexT (CcT DS.Empty,_))    = DS.Empty
seqFromFMIndexT (FMIndexT (_,OccCKT DS.Empty)) = DS.Empty
seqFromFMIndexT xs                             = do
  let xss = (\(OccCKT t) -> t) $
            (\(_,b) -> b)      $
            (\(FMIndexT t) -> t) xs
  iFFMIndexT xss
    where
      iFFMIndexT DS.Empty         = DS.Empty
      iFFMIndexT ((_,b) DS.:<| _) =
        fmap (\(_,_,e) -> e) b

{-------------------------------}