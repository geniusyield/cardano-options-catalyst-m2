{-# OPTIONS_GHC -Wno-orphans #-}

{- |
Module      : GeniusYield.Scripts.DEX.Option
Copyright   : (c) 2023 GYELD GMBH
License     : Apache 2.0
Maintainer  : support@geniusyield.com
Stability   : develop
-}
module GeniusYield.Scripts.DEX.Option
  ( -- * Constants
    optionMinAda

    -- * Validator
  , optionPolicy
  , optionValidator
  , noFeeConfigNft

    -- * CIP-68 reference-NFT lock
  , cip68ReferenceValidator

    -- * Datum
  , OptionDatum (..)

    -- * Redeemer
  , OnChain.OptionRedeemer (..)
  , mkOptionTokenRedeemer
  )
where

import GHC.Generics (Generic)
import GeniusYield.Types
import PlutusTx (FromData (fromBuiltinData), ToData (toBuiltinData))

import GeniusYield.OnChain.DEX.Option qualified as OnChain
import GeniusYield.OnChain.DEX.Option.CIP68Reference.Compiled qualified as OnChain
import GeniusYield.OnChain.DEX.Option.Compiled qualified as OnChain

deriving instance Show OnChain.OptionDatum

deriving instance Generic OnChain.OptionDatum

deriving instance Show OnChain.OptionRedeemer

deriving instance Generic OnChain.OptionRedeemer

data OptionDatum = OptionDatum
  { opdRef :: !GYTxOutRef
  , opdToken :: !GYAssetClass
  , opdStart :: !GYTime
  , opdEnd :: !GYTime
  , opdCancelCutoff :: !GYTime
  , opdDeposit :: !GYAssetClass
  , opdPayment :: !GYAssetClass
  , opdPrice :: !GYRational
  , opdSellerKey :: !GYPubKeyHash
  }
  deriving (Generic, Show)

instance ToData OptionDatum where
  toBuiltinData OptionDatum {..} =
    toBuiltinData
      OnChain.OptionDatum
        { OnChain.opdRef = txOutRefToPlutus opdRef
        , OnChain.opdToken = assetClassToPlutus opdToken
        , OnChain.opdStart = timeToPlutus opdStart
        , OnChain.opdEnd = timeToPlutus opdEnd
        , OnChain.opdCancelCutoff = timeToPlutus opdCancelCutoff
        , OnChain.opdDeposit = assetClassToPlutus opdDeposit
        , OnChain.opdPayment = assetClassToPlutus opdPayment
        , OnChain.opdPrice = rationalToPlutus opdPrice
        , OnChain.opdSellerKey = pubKeyHashToPlutus opdSellerKey
        }

instance FromData OptionDatum where
  fromBuiltinData d = do
    opd <- fromBuiltinData d
    ref <- fromEither $ txOutRefFromPlutus $ OnChain.opdRef opd
    token <- fromEither $ assetClassFromPlutus $ OnChain.opdToken opd
    deposit <- fromEither $ assetClassFromPlutus $ OnChain.opdDeposit opd
    payment <- fromEither $ assetClassFromPlutus $ OnChain.opdPayment opd
    sellerKey <- fromEither $ pubKeyHashFromPlutus $ OnChain.opdSellerKey opd
    return
      OptionDatum
        { opdRef = ref
        , opdToken = token
        , opdStart = timeFromPlutus $ OnChain.opdStart opd
        , opdEnd = timeFromPlutus $ OnChain.opdEnd opd
        , opdCancelCutoff = timeFromPlutus $ OnChain.opdCancelCutoff opd
        , opdDeposit = deposit
        , opdPayment = payment
        , opdPrice = rationalFromPlutus $ OnChain.opdPrice opd
        , opdSellerKey = sellerKey
        }
    where
      fromEither :: Either e a -> Maybe a
      fromEither = either (const Nothing) Just

optionMinAda :: GYValue
optionMinAda = either (error . show) id $ valueFromPlutus OnChain.optionMinAda

-- | Off-chain sentinel: ADA asset class used to signal "no protocol fees".
noFeeConfigNft :: GYAssetClass
noFeeConfigNft = GYLovelace

optionPolicy :: GYScript PlutusV2 -> GYAddress -> GYScript PlutusV2
optionPolicy nftPolicy addr =
  mintingPolicyFromPlutus
    $ OnChain.originalOptionPolicy
      (mintingPolicyCurrencySymbol nftPolicy)
      (addressToPlutus addr)

-- | Build the option validator, parameterised by the DEX NFT policy and the
-- fee-config NFT. Pass 'noFeeConfigNft' to deploy without protocol fees.
optionValidator :: GYScript PlutusV2 -> GYAssetClass -> GYScript PlutusV2
optionValidator nftPolicy feeConfigNft =
  validatorFromPlutus
    $ OnChain.originalOptionValidator
      (mintingPolicyCurrencySymbol nftPolicy)
      (assetClassToPlutus feeConfigNft)

mkOptionTokenRedeemer :: GYTxOutRef -> GYRedeemer
mkOptionTokenRedeemer = redeemerFromPlutusData . txOutRefToPlutus

-- | Always-fails lock for the CIP-68 reference NFT. The minted reference NFT
-- is sent here with the option-series metadata as an inline datum, making the
-- metadata permanently immutable (the UTxO can never be spent).
cip68ReferenceValidator :: GYScript PlutusV2
cip68ReferenceValidator = validatorFromPlutus OnChain.originalCIP68ReferenceValidator
