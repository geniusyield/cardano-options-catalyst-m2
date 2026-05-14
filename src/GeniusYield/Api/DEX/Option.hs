{- |
Module      : GeniusYield.Api.DEX.Option
Copyright   : (c) 2023 GYELD GMBH
License     : Apache 2.0
Maintainer  : support@geniusyield.com
Stability   : develop
-}
module GeniusYield.Api.DEX.Option
  ( OptionException (..)
  , OptionInfo (..)
  , optionAddress
  , optionInfos
  , optionInfo
  , createOption
  , createOptionWithCIP68
  , executeOption
  , retrieveOption
  , cancelEarlyOption
  )
where

import Control.Monad.Reader.Class (MonadReader (..))
import Data.Map.Strict qualified as Map
import Data.Swagger qualified as Swagger
import Data.Text (Text)
import Data.Text qualified as Text
import GeniusYield.HTTP.Errors
import GeniusYield.Imports
import GeniusYield.TxBuilder
  ( GYTxMonadException (GYApplicationException)
  , mustHaveRefInput
  )
import GeniusYield.TxBuilder.Class
import GeniusYield.Types
import Network.HTTP.Types (status400)

import GeniusYield.Api.DEX.Option.CIP68
  ( CIP68OptionMetadata
  , OptionType
  , cip68ReferenceTokenName
  , cip68UserTokenName
  , metadataFromOptionParams
  , toCIP68Datum
  )
import GeniusYield.Api.DEX.Utils (NftInfo (..), nftInfo, nftInfo')
import GeniusYield.Api.Types
import GeniusYield.OnChain.AnyMint.Compiled (originalAnyMintPolicy)
import GeniusYield.Scripts
import GeniusYield.Scripts.DEX
import GeniusYield.Scripts.DEX.Option (cip68ReferenceValidator, noFeeConfigNft)
import GeniusYield.Scripts.DEX.OptionFeeConfig (optionFeeConfigValidator)

-- | Permissive AnyMint policy used to mint the CIP-68 reference\/user NFT
-- pair. The DEX 'dexNftPolicy' enforces "exactly one token per tx", which
-- conflicts with minting three tokens (seller NFT + ref + user) in one
-- skeleton, so the CIP-68 pair lives under this separate policy.
anyMintPolicy :: GYScript PlutusV2
anyMintPolicy = mintingPolicyFromPlutus originalAnyMintPolicy

newtype OptionException = OptionDoesNotExist GYTxOutRef
  deriving stock Show
  deriving anyclass Exception

instance IsGYApiError OptionException where
  toApiError (OptionDoesNotExist ref) =
    GYApiError
      { gaeErrorCode = "OPTION_DOES_NOT_EXIST"
      , gaeHttpStatus = status400
      , gaeMsg = Text.pack $ printf "Option with ref %s does not exist." ref
      }

data OptionInfo = OptionInfo
  { opiRef :: !GYTxOutRef
  , opiOptionRef :: !GYTxOutRef
  , opiOptionToken :: !GYAssetClass
  , opiNFT :: !GYAssetClass
  , opiStart :: !GYTime
  , opiEnd :: !GYTime
  , opiCancelCutoff :: !GYTime
  , opiDepositToken :: !GYAssetClass
  , opiPaymentToken :: !GYAssetClass
  , opiPrice :: !GYRational
  , opiValue :: !GYValue
  , opiDepositAmt :: !Natural
  , opiPaymentAmt :: !Natural
  , opiSellerKey :: !GYPubKeyHash
  }
  deriving stock (Generic, Show)
  deriving anyclass (Swagger.ToSchema, ToJSON)

optionValidatorM :: GYApiQueryMonad m => m (GYScript PlutusV2)
optionValidatorM = do
  GYCompiledScripts {dexNftPolicy, dexOptionFeeConfigNft} <- ask
  return $ optionValidator dexNftPolicy (maybe noFeeConfigNft id dexOptionFeeConfigNft)

optionAddress :: GYApiQueryMonad m => m GYAddress
optionAddress = optionValidatorM >>= scriptAddress

optionPolicyM :: GYApiQueryMonad m => m (GYScript PlutusV2)
optionPolicyM = do
  GYCompiledScripts {dexNftPolicy} <- ask
  optionPolicy dexNftPolicy <$> optionAddress

optionToken :: GYApiQueryMonad m => GYTxOutRef -> m GYAssetClass
optionToken ref = do
  pid <- mintingPolicyId <$> optionPolicyM
  return $ GYToken pid $ expectedTokenName ref

optionInfos' :: GYApiQueryMonad m => [(GYUTxO, Maybe GYDatum)] -> m (Map GYTxOutRef OptionInfo)
optionInfos' utxosWithDatums = do
  addr <- optionAddress
  flip iwither (utxosDatumsPure utxosWithDatums) $ \oref (utxoAddr, utxoVal, OptionDatum {..}) ->
    if utxoAddr /= addr
      then return Nothing
      else do
        NftInfo {..} <- nftInfo' opdRef
        let
          v = utxoVal `valueMinus` optionMinAda
          depositAmt = valueAssetClass v opdDeposit
          paymentAmt = valueAssetClass v opdPayment
        if depositAmt < 0 || paymentAmt < 0
          then return Nothing
          else do
            token' <- optionToken opdRef
            return
              $ if opdToken /= token'
                then Nothing
                else
                  Just
                    OptionInfo
                      { opiRef = oref
                      , opiOptionRef = opdRef
                      , opiOptionToken = token'
                      , opiNFT = nftToken
                      , opiStart = opdStart
                      , opiEnd = opdEnd
                      , opiCancelCutoff = opdCancelCutoff
                      , opiDepositToken = opdDeposit
                      , opiPaymentToken = opdPayment
                      , opiPrice = opdPrice
                      , opiValue = utxoVal
                      , opiDepositAmt = fromInteger depositAmt
                      , opiPaymentAmt = fromInteger paymentAmt
                      , opiSellerKey = opdSellerKey
                      }

optionInfos :: GYApiQueryMonad m => m (Map GYTxOutRef OptionInfo)
optionInfos = do
  addr <- optionAddress
  utxosWithDatums <- utxosAtAddressesWithDatums [addr]
  optionInfos' utxosWithDatums

optionInfo :: GYApiQueryMonad m => GYTxOutRef -> m OptionInfo
optionInfo ref = do
  utxoWithDatum <- utxoAtTxOutRefWithDatum' ref
  infos <- optionInfos' [utxoWithDatum]
  case Map.lookup ref infos of
    Nothing -> throwError $ GYApplicationException $ OptionDoesNotExist ref
    Just info -> return info

optionDatumFromInfo :: OptionInfo -> OptionDatum
optionDatumFromInfo OptionInfo {..} =
  OptionDatum
    { opdRef = opiOptionRef
    , opdToken = opiOptionToken
    , opdStart = opiStart
    , opdEnd = opiEnd
    , opdCancelCutoff = opiCancelCutoff
    , opdDeposit = opiDepositToken
    , opdPayment = opiPaymentToken
    , opdPrice = opiPrice
    , opdSellerKey = opiSellerKey
    }

txInFromInfo :: GYApiQueryMonad m => OptionInfo -> OptionRedeemer -> m (GYTxIn PlutusV2)
txInFromInfo info@OptionInfo {..} r = do
  v <- optionValidatorM
  return
    GYTxIn
      { gyTxInTxOutRef = opiRef
      , gyTxInWitness =
          GYTxInWitnessScript
            (GYInScript v)
            (Just $ datumFromPlutusData $ optionDatumFromInfo info)
            (redeemerFromPlutusData r)
      }

createOption
  :: GYApiMonad m
  => GYTime
  -- ^ Start of the execution interval.
  -> GYTime
  -- ^ End of the execution interval.
  -> GYTime
  -- ^ Early-cancel cutoff: writer may cancel before this time via CancelEarly.
  -> GYAssetClass
  -- ^ The deposited token.
  -> GYAssetClass
  -- ^ The payment token.
  -> GYRational
  -- ^ The price (payment tokens per deposited token).
  -> Natural
  -- ^ The deposit amount.
  -> GYPubKeyHash
  -- ^ The seller key.
  -> m (GYTxSkeleton PlutusV2)
createOption start end cancelCutoff deposit payment price amount pkh = do
  NftInfo {..} <- nftInfo
  addr <- optionAddress
  tokenPolicy <- optionPolicyM

  let
    token = GYToken (mintingPolicyId tokenPolicy) nftName
    d =
      OptionDatum
        { opdRef = nftRef
        , opdStart = start
        , opdEnd = end
        , opdCancelCutoff = cancelCutoff
        , opdDeposit = deposit
        , opdPayment = payment
        , opdPrice = price
        , opdToken = token
        , opdSellerKey = pkh
        }
    amount' = toInteger amount
    v = optionMinAda <> valueSingleton deposit amount' <> valueSingleton nftToken 1

  return
    $ mustHaveInput
      ( GYTxIn
          { gyTxInTxOutRef = nftRef
          , gyTxInWitness = GYTxInWitnessKey
          }
      )
      <> mustHaveOutput
        ( GYTxOut
            { gyTxOutAddress = addr
            , gyTxOutValue = v
            , gyTxOutDatum = Just (datumFromPlutusData d, GYTxOutUseInlineDatum)
            , gyTxOutRefS = Nothing
            }
        )
      <> mustMint (GYMintScript nftPolicy) nftRedeemer nftName 1
      <> mustMint (GYMintScript tokenPolicy) (mkOptionTokenRedeemer nftRef) nftName amount'

-- | Same as 'createOption' but additionally mints a CIP-68 reference\/user
-- NFT pair under the AnyMint policy:
--
--  * The reference NFT (label 100, 'cip68ReferenceTokenName') is sent to the
--    'cip68ReferenceValidator' AlwaysFails address with the option-series
--    metadata as an inline datum — making the metadata permanent and
--    wallet-readable per CIP-68.
--
--  * The user NFT (label 222, 'cip68UserTokenName') lands in the seller\'s
--    change UTxO. Wallets (Lace, Eternl, pool.pm) resolve the user NFT to its
--    reference NFT via the CIP-67 prefix swap and render the metadata.
--
-- The seller NFT, option-payoff tokens, and validator UTxO are minted
-- exactly as in 'createOption' — so this function is purely additive on top
-- of the existing tx structure and the on-chain validator is unchanged.
createOptionWithCIP68
  :: GYApiMonad m
  => GYTime
  -- ^ Start of the execution interval.
  -> GYTime
  -- ^ End of the execution interval.
  -> GYTime
  -- ^ Early-cancel cutoff: writer may cancel before this time via CancelEarly.
  -> GYAssetClass
  -- ^ The deposited token.
  -> GYAssetClass
  -- ^ The payment token.
  -> GYRational
  -- ^ The price (payment tokens per deposited token).
  -> Natural
  -- ^ The deposit amount.
  -> GYPubKeyHash
  -- ^ The seller key.
  -> OptionType
  -- ^ Call or Put.
  -> Bool
  -- ^ Whether the seller can cancel early.
  -> Text
  -- ^ Display name (e.g. @"GeniusYield ADA→GENS Call · 0.5"@).
  -> Text
  -- ^ Image URI (@ipfs://...@ or @data:image/svg+xml;base64,...@).
  -> Text
  -- ^ Description.
  -> Text
  -- ^ Fee-config NFT reference (@"policyId.assetName"@ or empty).
  -> m (GYAssetClass, GYTxSkeleton PlutusV2)
  -- ^ Returns the reference-NFT asset class (so the API can echo it
  -- back) paired with the unsigned tx skeleton. Asset class comes first
  -- so the @Traversable ((,) GYAssetClass)@ instance lets server code
  -- thread it through @runSkeletonF@.
createOptionWithCIP68
  start end cancelCutoff deposit payment price amount pkh
  optType cancellable displayName imageUri description feeCfgRef = do
    NftInfo {..} <- nftInfo
    addr <- optionAddress
    tokenPolicy <- optionPolicyM
    cip68Addr <- scriptAddress cip68ReferenceValidator

    startSlot <- enclosingSlotFromTime' start
    endSlot   <- enclosingSlotFromTime' end

    let
      token = GYToken (mintingPolicyId tokenPolicy) nftName
      d =
        OptionDatum
          { opdRef = nftRef
          , opdStart = start
          , opdEnd = end
          , opdCancelCutoff = cancelCutoff
          , opdDeposit = deposit
          , opdPayment = payment
          , opdPrice = price
          , opdToken = token
          , opdSellerKey = pkh
          }
      amount' = toInteger amount
      validatorValue =
        optionMinAda
          <> valueSingleton deposit amount'
          <> valueSingleton nftToken 1

      refTokenName  = cip68ReferenceTokenName nftRef
      userTokenName = cip68UserTokenName nftRef
      anyMintPolicyId = mintingPolicyId anyMintPolicy
      refAsset      = GYToken anyMintPolicyId refTokenName
      anyMintRedeemer = unitRedeemer

      metadata =
        metadataFromOptionParams
          displayName
          imageUri
          description
          deposit
          payment
          price
          (slotToInteger startSlot)
          (slotToInteger endSlot)
          optType
          cancellable
          feeCfgRef

      cip68RefValue = optionMinAda <> valueSingleton refAsset 1

    return
      -- The user NFT is minted but has no explicit output — Atlas\'s
      -- change-balancing emits it in the seller\'s change UTxO automatically,
      -- which keeps it in the seller\'s wallet (CIP-30 will list it).
      ( refAsset
      , mustHaveInput
          ( GYTxIn
              { gyTxInTxOutRef = nftRef
              , gyTxInWitness = GYTxInWitnessKey
              }
          )
          <> mustHaveOutput
            ( GYTxOut
                { gyTxOutAddress = addr
                , gyTxOutValue = validatorValue
                , gyTxOutDatum = Just (datumFromPlutusData d, GYTxOutUseInlineDatum)
                , gyTxOutRefS = Nothing
                }
            )
          <> mustHaveOutput
            ( GYTxOut
                { gyTxOutAddress = cip68Addr
                , gyTxOutValue = cip68RefValue
                , gyTxOutDatum = Just (datumFromPlutus (toCIP68Datum metadata), GYTxOutUseInlineDatum)
                , gyTxOutRefS = Nothing
                }
            )
          <> mustMint (GYMintScript nftPolicy) nftRedeemer nftName 1
          <> mustMint (GYMintScript anyMintPolicy) anyMintRedeemer refTokenName 1
          <> mustMint (GYMintScript anyMintPolicy) anyMintRedeemer userTokenName 1
          <> mustMint (GYMintScript tokenPolicy) (mkOptionTokenRedeemer nftRef) nftName amount'
      )

executeOption
  :: GYApiMonad m
  => GYTxOutRef
  -> Natural
  -> m (GYTxSkeleton PlutusV2)
executeOption ref amt = do
  let amt' = toInteger amt

  GYCompiledScripts {dexOptionFeeConfigNft} <- ask
  info@OptionInfo {..} <- optionInfo ref
  txIn <- txInFromInfo info $ Execute amt'
  nowSlot <- slotOfCurrentBlock
  nowTime <- slotToBeginTime nowSlot
  laterSlot <- enclosingSlotFromTime' $ addSeconds nowTime 120 -- two minutes from now
  endSlot <- enclosingSlotFromTime' $ addSeconds opiEnd (-2)
  addr <- optionAddress
  policy <- optionPolicyM

  -- When a fee-config NFT is configured, find the fee config UTxO and include
  -- it as a reference input so the on-chain validator can read the fee datum.
  mFeeConfigRef <- case dexOptionFeeConfigNft of
    Nothing -> return Nothing
    Just feeNft -> do
      feeConfigAddr <- scriptAddress $ optionFeeConfigValidator feeNft
      utxos <- utxosAtAddress feeConfigAddr $ Just feeNft
      return $ case utxosToList utxos of
        (u : _) -> Just (utxoRef u)
        []      -> Nothing

  let
    price = ceiling $ toRational amt' * toRational opiPrice
    v =
      opiValue
        <> valueNegate (valueSingleton opiDepositToken amt')
        <> valueSingleton opiPaymentToken price
    d = optionDatumFromInfo info
    tn = expectedTokenName opiOptionRef
    feeRefSkeleton = maybe mempty mustHaveRefInput mFeeConfigRef

  return
    $ mustHaveInput txIn
      <> isInvalidBefore nowSlot
      <> isInvalidAfter (min laterSlot endSlot)
      <> mustMint (GYMintScript policy) (mkOptionTokenRedeemer opiOptionRef) tn (-amt')
      <> mustHaveOutput
        GYTxOut
          { gyTxOutAddress = addr
          , gyTxOutValue = v
          , gyTxOutDatum = Just (datumFromPlutusData d, GYTxOutUseInlineDatum)
          , gyTxOutRefS = Nothing
          }
      <> feeRefSkeleton

retrieveOption
  :: GYApiMonad m
  => GYTxOutRef
  -> m (GYTxSkeleton PlutusV2)
retrieveOption ref = do
  info@OptionInfo {..} <- optionInfo ref
  txIn <- txInFromInfo info Retrieve
  slot <- slotOfCurrentBlock
  NftInfo {..} <- nftInfo' opiOptionRef
  return
    $ mustBeSignedBy opiSellerKey
      <> mustHaveInput txIn
      <> isInvalidBefore slot
      <> mustMint (GYMintScript nftPolicy) (mkNftRedeemer Nothing) nftName (-1)

cancelEarlyOption
  :: GYApiMonad m
  => GYTxOutRef
  -> m (GYTxSkeleton PlutusV2)
cancelEarlyOption ref = do
  info@OptionInfo {..} <- optionInfo ref
  txIn <- txInFromInfo info CancelEarly
  NftInfo {..} <- nftInfo' opiOptionRef
  tokenPolicy <- optionPolicyM
  cutoffSlot <- enclosingSlotFromTime' $ addSeconds opiCancelCutoff (-2)
  let
    amt = toInteger opiDepositAmt
    tn  = expectedTokenName opiOptionRef
  return
    $ mustBeSignedBy opiSellerKey
      <> mustHaveInput txIn
      <> isInvalidAfter cutoffSlot
      <> mustMint (GYMintScript tokenPolicy) (mkOptionTokenRedeemer opiOptionRef) tn (negate amt)
      <> mustMint (GYMintScript nftPolicy) (mkNftRedeemer Nothing) nftName (-1)
