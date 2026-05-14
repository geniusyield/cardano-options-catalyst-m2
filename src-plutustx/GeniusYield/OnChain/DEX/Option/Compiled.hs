{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TemplateHaskell #-}

{- |
Module      : GeniusYield.OnChain.DEX.Option.Compiled
Copyright   : (c) 2023 GYELD GMBH
License     : Apache 2.0
Maintainer  : support@geniusyield.com
Stability   : develop
-}
module GeniusYield.OnChain.DEX.Option.Compiled
  ( originalOptionPolicy
  , originalOptionValidator
  )
where

import PlutusCore.Version (plcVersion100)
import PlutusLedgerApi.V1.Value
import PlutusLedgerApi.V2
import PlutusTx qualified

import GeniusYield.OnChain.DEX.Option (mkOptionPolicy, mkOptionValidator)

originalOptionValidator
  :: CurrencySymbol
  -> AssetClass
  -- ^ Fee-config NFT. Pass 'noFeeConfigNft' (ADA) to disable fees.
  -> PlutusTx.CompiledCode (PlutusTx.BuiltinData -> PlutusTx.BuiltinData -> PlutusTx.BuiltinData -> ())
originalOptionValidator nftSymbol feeConfigNft =
  $$(PlutusTx.compile [||mkOptionValidator||])
    `PlutusTx.unsafeApplyCode` PlutusTx.liftCode plcVersion100 nftSymbol
    `PlutusTx.unsafeApplyCode` PlutusTx.liftCode plcVersion100 feeConfigNft

originalOptionPolicy :: CurrencySymbol -> Address -> PlutusTx.CompiledCode (PlutusTx.BuiltinData -> PlutusTx.BuiltinData -> ())
originalOptionPolicy nftSymbol addr =
  $$(PlutusTx.compile [||mkOptionPolicy||])
    `PlutusTx.unsafeApplyCode` PlutusTx.liftCode plcVersion100 nftSymbol
    `PlutusTx.unsafeApplyCode` PlutusTx.liftCode plcVersion100 addr
