{-# LANGUAGE MultiWayIf   #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE Strict       #-}


-- |
-- Module      :  Data.BWT
-- Copyright   :  (c) Matthew Mosior 2022
-- License     :  BSD-style
-- Maintainer  :  mattm.github@gmail.com
-- Portability :  portable
--
-- = Burrows-Wheeler Transform (BWT)
-- 
-- The two functions that most users will utilize are 'toBWT' and 'fromBWT'.
-- There are auxilary function(s) inside of @"Data.BWT.Internal"@.
--
-- The helper functions for ByteString, 'bytestringToBWT' and 'bytestringFromBWT' and Text, 'textToBWT' and 'textFromBWT' should help for common use cases.
--
-- @"Data.BWT.Internal"@ also has the function 'createBWTMatrix', which can be useful as well, although not used by either 'toBWT' or 'fromBWT'.


module Data.BWT where

import Data.BWT.Internal

import Control.Monad()
import Control.Monad.ST as CMST
import Control.Monad.State.Strict()
import Data.ByteString as BS (ByteString,pack,unpack)
import Data.Foldable as DFold (toList)
import Data.Sequence as DS
import Data.STRef()
import Data.Text (Text)
import Data.Text.Encoding as DTE (decodeUtf8,encodeUtf8)
import Data.Word (Word8)


{-toBWT Function(s)-}

-- | Takes a String and returns the Burrows-Wheeler Transform (BWT).
-- Implemented via a 'SuffixArray'.
toBWT :: Ord a =>
         [a]   ->
         BWT a
toBWT [] = DS.Empty
toBWT xs = do
  let saxs = createSuffixArray xss
  saToBWT saxs
          xss
    where
      xss = DS.fromList xs

-- | Helper function for converting a 'ByteString'
-- to a 'BWT' 'Word8'.
bytestringToBWT :: ByteString ->
                   BWT Word8
bytestringToBWT = toBWT . BS.unpack

-- newtype to ensure you only uncompress a BWT created
-- from textToBWT, since [Word8] -> Text is partial
newtype TextBWT = TextBWT (BWT Word8)

-- | Helper function for converting 'Text'
-- to a 'TextBWT'.
textToBWT :: Text ->
             TextBWT
textToBWT = TextBWT . bytestringToBWT . DTE.encodeUtf8

{-------------------}


{-fromBWT function(s)-}

-- | Takes a BWT data type (please see @"Data.BWT.Internal"@) and inverts it back to the original string.
-- 
-- This function utilizes the state monad (strict) in order
-- to implement the [Magic](https://www.youtube.com/watch?v=QwSsppKrCj4) Inverse BWT algorithm by backtracking
-- indices starting with the (__Nothing__,_) entry.
fromBWT :: Ord a =>
           BWT a ->
           [a]
fromBWT bwt = do
  let originall = CMST.runST $ magicInverseBWT magicsz
  DFold.toList originall
    where
      magicsz = DS.sortBy (\(a,b) (c,d) -> sortTB (a,b) (c,d))
                zipped
      zipped  = DS.zip bwt
                       (DS.iterateN (DS.length bwt) (+1) 0)

-- | Helper function for converting a 'BWT' 'Word8'
-- to a 'ByteString'.
bytestringFromBWT :: BWT Word8 ->
                     ByteString
bytestringFromBWT = BS.pack . fromBWT

-- | Helper function for converting 'TextBWT'
-- to a 'Text'
textFromBWT :: TextBWT -> Text
textFromBWT (TextBWT x) = DTE.decodeUtf8 $
                          bytestringFromBWT x

{---------------------}
