{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TemplateHaskell #-}

{- |
Module      : GeniusYield.OnChain.DEX.Option.CIP68Reference.Compiled
Copyright   : (c) 2026 GYELD GMBH
License     : Apache 2.0
Maintainer  : support@geniusyield.com
Stability   : develop

Compiled bytecode for the CIP-68 reference-NFT lock validator
(see "GeniusYield.OnChain.DEX.Option.CIP68Reference"). Wallets,
explorers, and the off-chain builder consume this via its compiled
script hash (and the address derived from it).
-}
module GeniusYield.OnChain.DEX.Option.CIP68Reference.Compiled
  ( originalCIP68ReferenceValidator
  ) where

import PlutusTx qualified

import GeniusYield.OnChain.DEX.Option.CIP68Reference

originalCIP68ReferenceValidator
  :: PlutusTx.CompiledCode
       (PlutusTx.BuiltinData -> PlutusTx.BuiltinData -> PlutusTx.BuiltinData -> ())
originalCIP68ReferenceValidator =
  $$(PlutusTx.compile [|| mkCIP68ReferenceValidator ||])
