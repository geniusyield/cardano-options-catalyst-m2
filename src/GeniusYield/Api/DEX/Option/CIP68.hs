{- |
Module      : GeniusYield.Api.DEX.Option.CIP68
Copyright   : (c) 2026 GYELD GMBH
License     : Apache 2.0
Maintainer  : support@geniusyield.com
Stability   : develop

CIP-68 datum-metadata for option series.

Each option series mints a paired set of CIP-68 NFTs under the same
minting policy:

  * Reference NFT (label 100, asset-name prefix 0x000643b0) — lives at a
    reference script address with this metadata as its inline datum.
  * User NFT      (label 222, asset-name prefix 0x000de140) — held by the
    buyer, carries the right to exercise.

The two NFTs share the asset-name body so wallets can resolve the user
NFT to its reference NFT by swapping the four-byte label prefix.

This module is the pure data spec — serializing the metadata to a Plutus
data value the minting policy attaches to the reference NFT's UTxO.
It does NOT touch the on-chain validator (see "GeniusYield.OnChain.DEX.Option")
or the off-chain tx builder (see "GeniusYield.Api.DEX.Option").
-}
module GeniusYield.Api.DEX.Option.CIP68
  ( -- * Types
    CIP68OptionMetadata (..)
  , OptionType (..)
    -- * Asset-name labels (CIP-67)
  , labelReferenceNftPrefix
  , labelUserNftPrefix
  , makeReferenceAssetName
  , makeUserAssetName
  , swapLabelPrefix
    -- * Per-series asset names (derived from the consumed TxOutRef)
  , cip68BodyForRef
  , cip68ReferenceTokenName
  , cip68UserTokenName
    -- * Serialization to Plutus data
  , toCIP68Datum
  , metadataMap
    -- * Convenience constructors
  , exampleCallSeries
  , examplePutSeries
  , metadataFromOptionParams
  ) where

import Control.Lens ((.~), (?~))
import Crypto.Hash (Digest, SHA256, hash)
import Data.Aeson (withText)
import Data.ByteArray qualified as BA
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.Function ((&))
import Data.Swagger qualified as Swagger
import Data.Swagger.Internal.Schema qualified as Swagger
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import GeniusYield.Imports
import GeniusYield.Types
  ( GYAssetClass (..)
  , GYRational
  , GYTokenName (..)
  , GYTxOutRef
  , mintingPolicyIdToText
  , rationalToGHC
  , tokenNameToHex
  , txOutRefToTuple'
  )

import PlutusLedgerApi.V2 qualified as Plutus

-- ---------------------------------------------------------------------------
-- Option type tag
-- ---------------------------------------------------------------------------

data OptionType = OptionCall | OptionPut
  deriving stock (Eq, Show, Generic)

optionTypeText :: OptionType -> Text
optionTypeText OptionCall = "call"
optionTypeText OptionPut  = "put"

instance ToJSON OptionType where
  toJSON = toJSON . optionTypeText

instance FromJSON OptionType where
  parseJSON = withText "OptionType" $ \t -> case T.toLower t of
    "call" -> pure OptionCall
    "put"  -> pure OptionPut
    other  -> fail $ "OptionType: expected \"call\" or \"put\", got " <> show other

instance Swagger.ToSchema OptionType where
  declareNamedSchema _ =
    pure
      $ Swagger.named "OptionType"
      $ mempty
        & Swagger.type_ ?~ Swagger.SwaggerString
        & Swagger.enum_ ?~ [toJSON ("call" :: Text), toJSON ("put" :: Text)]
        & Swagger.description
        ?~ "Either \"call\" or \"put\" — the option payoff direction."

-- ---------------------------------------------------------------------------
-- The metadata payload
-- ---------------------------------------------------------------------------

-- | Full set of fields stored in the reference NFT's inline datum.
--
-- The first three fields (@name@\/@image@\/@description@) satisfy the
-- core CIP-25\/CIP-68 contract that wallets like Lace, Eternl, and pool.pm
-- already render. The remaining fields are the M3 acceptance-criteria
-- payload — domain-specific option terms that custom tooling can read
-- directly from chain.
data CIP68OptionMetadata = CIP68OptionMetadata
  { cipName        :: !Text   -- ^ Human-readable series name, e.g. "GENS Call \@ 0.5 · 2026-05-12".
  , cipImage       :: !Text   -- ^ @ipfs:\/\/...@ or @data:image\/svg+xml;base64,...@.
  , cipDescription :: !Text
    -- M3 fields
  , cipDepositPolicy  :: !Text  -- ^ Hex policy id of the asset locked by the seller (empty = ADA).
  , cipDepositAsset   :: !Text  -- ^ Hex asset name of the deposit (empty = ADA).
  , cipPaymentPolicy  :: !Text  -- ^ Hex policy id the buyer pays in.
  , cipPaymentAsset   :: !Text  -- ^ Hex asset name of the payment asset.
  , cipStrike         :: !Text  -- ^ Decimal string, e.g. @"0.5"@.
  , cipStartSlot      :: !Integer
  , cipEndSlot        :: !Integer
  , cipOptionType     :: !OptionType
  , cipCancellable    :: !Bool
  , cipFeeCfgRef      :: !Text  -- ^ "policyId.assetName" of the fee-config NFT, or empty.
  } deriving stock (Eq, Show)

-- ---------------------------------------------------------------------------
-- CIP-67 label prefixes
-- ---------------------------------------------------------------------------

-- | Four-byte prefix for reference NFTs (label 100, CRC-checksum padded).
labelReferenceNftPrefix :: BS.ByteString
labelReferenceNftPrefix = BS.pack [0x00, 0x06, 0x43, 0xb0]

-- | Four-byte prefix for user NFTs (label 222).
labelUserNftPrefix :: BS.ByteString
labelUserNftPrefix = BS.pack [0x00, 0x0d, 0xe1, 0x40]

-- | Prepend the reference-NFT prefix to a series identifier.
makeReferenceAssetName :: BS.ByteString -> BS.ByteString
makeReferenceAssetName body = labelReferenceNftPrefix <> body

-- | Prepend the user-NFT prefix to a series identifier.
makeUserAssetName :: BS.ByteString -> BS.ByteString
makeUserAssetName body = labelUserNftPrefix <> body

-- | Swap a reference-NFT prefix for a user-NFT prefix (or vice versa).
-- Returns 'Nothing' if the input doesn't start with a known CIP-67 prefix.
swapLabelPrefix :: BS.ByteString -> Maybe BS.ByteString
swapLabelPrefix bs
  | labelReferenceNftPrefix `BS.isPrefixOf` bs =
      Just (labelUserNftPrefix <> BS.drop 4 bs)
  | labelUserNftPrefix `BS.isPrefixOf` bs =
      Just (labelReferenceNftPrefix <> BS.drop 4 bs)
  | otherwise = Nothing

-- ---------------------------------------------------------------------------
-- Per-series asset names
-- ---------------------------------------------------------------------------

-- | 28-byte body derived from the consumed @GYTxOutRef@ — the first 28
-- bytes of @SHA-256(ix \|\| txid)@. Mirrors the on-chain
-- 'GeniusYield.OnChain.Core.Common.Utils.expectedTwoTokenName' shape so
-- the body can be re-derived during validation, and leaves room for the
-- 4-byte CIP-67 label prefix inside Cardano's 32-byte asset-name limit.
cip68BodyForRef :: GYTxOutRef -> BS.ByteString
cip68BodyForRef ref =
  let (txIdHex, ix) = txOutRefToTuple' ref
      tidBytes = case Base16.decode (TE.encodeUtf8 txIdHex) of
        Right bs -> bs
        Left _   -> error "cip68BodyForRef: TxId hex was not valid base16"
      ixByte   = fromIntegral (ix `mod` 256) :: Word8
      preimage = BS.cons ixByte tidBytes
      digest   = hash preimage :: Digest SHA256
   in BS.take 28 (BS.pack (BA.unpack digest))

-- | Reference-NFT asset name for the given series: label 100 prefix
-- concatenated with 'cip68BodyForRef'.
cip68ReferenceTokenName :: GYTxOutRef -> GYTokenName
cip68ReferenceTokenName ref = GYTokenName (labelReferenceNftPrefix <> cip68BodyForRef ref)

-- | User-NFT asset name for the given series: label 222 prefix
-- concatenated with 'cip68BodyForRef'.
cip68UserTokenName :: GYTxOutRef -> GYTokenName
cip68UserTokenName ref = GYTokenName (labelUserNftPrefix <> cip68BodyForRef ref)

-- ---------------------------------------------------------------------------
-- Plutus-data serialization
-- ---------------------------------------------------------------------------

-- | CIP-68 datum is: @Constr 0 [metadata_map, version, extra]@.
--
-- @version@ is currently fixed at @1@ per the spec; @extra@ is set to
-- the unit @Constr 0 []@ — wallets ignore it.
toCIP68Datum :: CIP68OptionMetadata -> Plutus.Datum
toCIP68Datum m =
  Plutus.Datum
    $ Plutus.dataToBuiltinData
    $ Plutus.Constr 0
        [ metadataMap m
        , Plutus.I 1                       -- version
        , Plutus.Constr 0 []               -- extra (Unit)
        ]

-- | Build the @(Map ByteString PlutusData)@ that goes in slot 0 of the datum.
metadataMap :: CIP68OptionMetadata -> Plutus.Data
metadataMap m = Plutus.Map
  [ k "name"           ~> txt (cipName m)
  , k "image"          ~> txt (cipImage m)
  , k "description"    ~> txt (cipDescription m)
  , k "deposit_policy" ~> txt (cipDepositPolicy m)
  , k "deposit_asset"  ~> txt (cipDepositAsset m)
  , k "payment_policy" ~> txt (cipPaymentPolicy m)
  , k "payment_asset"  ~> txt (cipPaymentAsset m)
  , k "strike"         ~> txt (cipStrike m)
  , k "start_slot"     ~> Plutus.I (cipStartSlot m)
  , k "end_slot"       ~> Plutus.I (cipEndSlot m)
  , k "type"           ~> txt (optionTypeText (cipOptionType m))
  , k "cancellable"    ~> Plutus.I (if cipCancellable m then 1 else 0)
  , k "fee_cfg_ref"    ~> txt (cipFeeCfgRef m)
  ]
  where
    k :: Text -> Plutus.Data
    k = Plutus.B . TE.encodeUtf8

    txt :: Text -> Plutus.Data
    txt = Plutus.B . TE.encodeUtf8

    (~>) :: Plutus.Data -> Plutus.Data -> (Plutus.Data, Plutus.Data)
    a ~> b = (a, b)

-- ---------------------------------------------------------------------------
-- Default series for the M3 demo
-- ---------------------------------------------------------------------------

-- | Sample CALL series for the M3 demonstration:
-- ADA → GENS, strike 0.5, cancellable.
exampleCallSeries :: CIP68OptionMetadata
exampleCallSeries = CIP68OptionMetadata
  { cipName           = "GeniusYield ADA→GENS Call · strike 0.5"
  , cipImage          = "data:image/svg+xml;base64,PLACEHOLDER_LOGO"
  , cipDescription    =
      "European-style call option: the buyer may exchange ADA for GENS at "
      <> "strike 0.5 within the active window. Cancellable by the seller "
      <> "before the cutoff."
  , cipDepositPolicy  = ""        -- ADA
  , cipDepositAsset   = ""
  , cipPaymentPolicy  = "dda5fdb1002f7389b33e036b6afee82a8189becb6cba852e8b79b4fb"
  , cipPaymentAsset   = "0014df1047454e53"  -- GENS in hex
  , cipStrike         = "0.5"
  , cipStartSlot      = 0
  , cipEndSlot        = 0
  , cipOptionType     = OptionCall
  , cipCancellable    = True
  , cipFeeCfgRef      = ""
  }

-- ---------------------------------------------------------------------------
-- Building metadata from option params
-- ---------------------------------------------------------------------------

-- | Derive a fully-formed 'CIP68OptionMetadata' from the on-chain option
-- parameters plus the human-readable display fields.
--
-- This is the single source of truth used by the @createOption@ builder:
-- structural fields (deposit/payment policy, asset hex, strike, slots,
-- type, cancellable) are derived from the same parameters that go into
-- the @OptionDatum@, so the wallet-visible metadata cannot drift from
-- the on-chain terms.
metadataFromOptionParams
  :: Text          -- ^ Display name (e.g. @"GeniusYield ADA→GENS Call · 0.5"@)
  -> Text          -- ^ Image URI (e.g. @"ipfs://..."@ or @"data:image/svg+xml;base64,..."@)
  -> Text          -- ^ Description
  -> GYAssetClass  -- ^ Deposit asset
  -> GYAssetClass  -- ^ Payment asset
  -> GYRational    -- ^ Strike price (payment per deposit)
  -> Integer       -- ^ Start slot
  -> Integer       -- ^ End slot
  -> OptionType    -- ^ Call or Put
  -> Bool          -- ^ Cancellable
  -> Text          -- ^ Fee-config NFT reference (\"policyId.assetName\" or empty)
  -> CIP68OptionMetadata
metadataFromOptionParams nm img desc deposit payment strike startSlot endSlot otype cancellable feeCfg =
  let (depPol, depAsset)   = assetClassParts deposit
      (payPol, payAsset)   = assetClassParts payment
   in CIP68OptionMetadata
        { cipName          = nm
        , cipImage         = img
        , cipDescription   = desc
        , cipDepositPolicy = depPol
        , cipDepositAsset  = depAsset
        , cipPaymentPolicy = payPol
        , cipPaymentAsset  = payAsset
        , cipStrike        = T.pack (show (fromRational (rationalToGHC strike) :: Double))
        , cipStartSlot     = startSlot
        , cipEndSlot       = endSlot
        , cipOptionType    = otype
        , cipCancellable   = cancellable
        , cipFeeCfgRef     = feeCfg
        }
  where
    assetClassParts :: GYAssetClass -> (Text, Text)
    assetClassParts GYLovelace          = ("", "")
    assetClassParts (GYToken pid tn)    = (mintingPolicyIdToText pid, tokenNameToHex tn)

-- | Sample PUT series for the M3 demonstration:
-- GENS → ADA, strike 0.6, non-cancellable.
examplePutSeries :: CIP68OptionMetadata
examplePutSeries = CIP68OptionMetadata
  { cipName           = "GeniusYield GENS→ADA Put · strike 0.6"
  , cipImage          = "data:image/svg+xml;base64,PLACEHOLDER_LOGO"
  , cipDescription    =
      "European-style put option: the buyer may exchange GENS for ADA at "
      <> "strike 0.6 within the active window. Non-cancellable once minted."
  , cipDepositPolicy  = "dda5fdb1002f7389b33e036b6afee82a8189becb6cba852e8b79b4fb"
  , cipDepositAsset   = "0014df1047454e53"
  , cipPaymentPolicy  = ""        -- ADA
  , cipPaymentAsset   = ""
  , cipStrike         = "0.6"
  , cipStartSlot      = 0
  , cipEndSlot        = 0
  , cipOptionType     = OptionPut
  , cipCancellable    = False
  , cipFeeCfgRef      = ""
  }
