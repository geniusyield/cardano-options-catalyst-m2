{-# LANGUAGE NoImplicitPrelude #-}
{-# OPTIONS -fno-strictness -fno-spec-constr -fno-specialise #-}

{- |
Module      : GeniusYield.OnChain.DEX.Option.CIP68Reference
Copyright   : (c) 2026 GYELD GMBH
License     : Apache 2.0
Maintainer  : support@geniusyield.com
Stability   : develop

CIP-68 reference-NFT lock validator for the option-series metadata.

When an option series is created, a paired CIP-68 reference NFT
(asset-name prefix 0x000643b0) is minted alongside the existing seller
and option tokens. The reference NFT is sent to an output at this
validator's address with the option metadata as an inline datum.

This validator always fails — making the reference NFT permanently
locked, and the metadata datum therefore immutable. That is the standard
CIP-68 pattern for option series where the on-chain terms (strike,
window, type, cancellable…) are fixed at mint and must never change.

The pure CIP-68 metadata type and serializer live in
"GeniusYield.Api.DEX.Option.CIP68" — this module is only the on-chain
lock. The off-chain @createOption@ builder (in
"GeniusYield.Api.DEX.Option") places the reference NFT at the address
returned by this script's hash with the inline CIP-68 datum.
-}
module GeniusYield.OnChain.DEX.Option.CIP68Reference
  ( mkCIP68ReferenceValidator
  ) where

import PlutusLedgerApi.V2 (BuiltinData)
import PlutusTx.Prelude (Bool (..), error)

-- | Always-fails validator: the reference NFT can never be spent, so the
-- inline CIP-68 metadata datum at this address is permanently fixed.
--
-- The three @BuiltinData@ parameters are the standard Plutus V2 validator
-- arguments — @datum@, @redeemer@, @scriptContext@. We ignore all three
-- and force a CEK error, which the script interpreter reports as
-- validation failure. This is the textbook \"AlwaysFails\" pattern for
-- locking a UTxO permanently.
{-# INLINEABLE mkCIP68ReferenceValidator #-}
mkCIP68ReferenceValidator :: BuiltinData -> BuiltinData -> BuiltinData -> ()
mkCIP68ReferenceValidator _datum _redeemer _ctx = error ()
