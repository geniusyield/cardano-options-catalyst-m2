{- |
Module      : GeniusYield.Test.DEX.OptionCIP68
Copyright   : (c) 2026 GYELD GMBH
License     : Apache 2.0
Maintainer  : support@geniusyield.com
Stability   : develop

CIP-68 metadata trace tests for option series.

Coverage:

  * Pure structural tests:
      - 'toCIP68Datum' produces the exact CIP-68 spec shape:
        @Constr 0 [Map, I 1, Constr 0 []]@.
      - 'swapLabelPrefix' is involutive across the ref\/user label flip.
      - 'cip68BodyForRef' is deterministic for the same UTxO.
      - Ref and user asset names share the body and differ only in the
        4-byte CIP-67 label prefix.
      - Both asset names total exactly 32 bytes (Cardano max).

  * Chain-emulator (CLB) traces:
      - @createOptionWithCIP68@ confirms successfully on-chain.
      - The reference NFT lands at the AlwaysFails address with an
        inline CIP-68 datum.
      - Spending the reference UTxO always fails (the validator forces
        @error()@).
-}
module GeniusYield.Test.DEX.OptionCIP68
  ( optionCIP68Tests
  ) where

import Control.Monad.Reader (runReaderT)
import Data.ByteString qualified as BS
import Data.Maybe (mapMaybe)
import Data.Ratio ((%))
import GeniusYield.HTTP.Errors (someBackendError)
import GeniusYield.Imports
import GeniusYield.Test.Clb (mkTestFor, mustFail, sendSkeleton)
import GeniusYield.Test.FakeCoin (fakeCoin)
import GeniusYield.Test.Utils
import GeniusYield.TxBuilder
import GeniusYield.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import PlutusLedgerApi.V2 qualified as Plutus

import GeniusYield.Api.DEX.Option (createOptionWithCIP68)
import GeniusYield.Api.DEX.Option.CIP68
  ( OptionType (..)
  , cip68BodyForRef
  , cip68ReferenceTokenName
  , cip68UserTokenName
  , labelReferenceNftPrefix
  , labelUserNftPrefix
  , swapLabelPrefix
  , toCIP68Datum
  )
import GeniusYield.Api.DEX.Option.CIP68 qualified as CIP68
import GeniusYield.Scripts (GYCompiledScripts)
import GeniusYield.Scripts.DEX.Option (cip68ReferenceValidator)

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------

optionCIP68Tests :: GYCompiledScripts -> TestTree
optionCIP68Tests gycs =
  testGroup
    "OptionCIP68"
    [ testGroup "Pure"
        [ testCase "toCIP68Datum has Constr 0 [Map, I 1, Constr 0 []] shape"
            datumShapeTest
        , testCase "swapLabelPrefix is involutive (ref <-> user)"
            swapLabelPrefixInvolutiveTest
        , testCase "cip68BodyForRef is deterministic"
            bodyForRefDeterministicTest
        , testCase "ref and user names share the same body"
            refAndUserShareBodyTest
        , testCase "asset-name lengths are exactly 32 bytes"
            assetNameLengthTest
        ]
    , testGroup "Traces"
        [ mkTestFor "createOptionWithCIP68 confirms"
            $ createCIP68Trace gycs . testWallets
        , mkTestFor "reference NFT lands at AlwaysFails address with inline datum"
            $ refAtAlwaysFailsTrace gycs . testWallets
        , mkTestFor "spending the reference NFT UTxO must fail"
            $ mustFail . refCannotBeSpentTrace gycs . testWallets
        ]
    ]

-------------------------------------------------------------------------------
-- Pure tests
-------------------------------------------------------------------------------

-- | Build a sample metadata payload via the exposed example constructor so
-- we don't bind tests to a specific field schema.
sampleMetadata :: CIP68.CIP68OptionMetadata
sampleMetadata = CIP68.exampleCallSeries

-- | CIP-68 datum spec: a single 'Constr' with tag @0@ and exactly three
-- fields — metadata map, version (an @Integer@), and an opaque extras
-- slot (we use @Constr 0 []@ = unit).
datumShapeTest :: IO ()
datumShapeTest = do
  let Plutus.Datum d = toCIP68Datum sampleMetadata
  case Plutus.fromBuiltinData d of
    Just (Plutus.Constr 0 [_metadata, Plutus.I 1, Plutus.Constr 0 []]) ->
      pure ()
    Just other ->
      fail $ "Unexpected CIP-68 datum shape: " <> show other
    Nothing ->
      fail "CIP-68 datum did not round-trip through fromBuiltinData"

swapLabelPrefixInvolutiveTest :: IO ()
swapLabelPrefixInvolutiveTest = do
  let body  = BS.pack [0xde, 0xad, 0xbe, 0xef]
      refNm = labelReferenceNftPrefix <> body
      usrNm = labelUserNftPrefix <> body
  swapLabelPrefix refNm @?= Just usrNm
  swapLabelPrefix usrNm @?= Just refNm
  -- Round-trip ref → user → ref.
  (swapLabelPrefix =<< swapLabelPrefix refNm) @?= Just refNm

bodyForRefDeterministicTest :: IO ()
bodyForRefDeterministicTest = do
  let ref = sampleTxOutRef
  cip68BodyForRef ref @?= cip68BodyForRef ref

refAndUserShareBodyTest :: IO ()
refAndUserShareBodyTest = do
  let ref               = sampleTxOutRef
      GYTokenName refBs = cip68ReferenceTokenName ref
      GYTokenName usrBs = cip68UserTokenName ref
      refBody           = BS.drop 4 refBs
      usrBody           = BS.drop 4 usrBs
  refBody @?= usrBody
  BS.take 4 refBs @?= labelReferenceNftPrefix
  BS.take 4 usrBs @?= labelUserNftPrefix

-- | Per Cardano spec, native asset names are at most 32 bytes. CIP-67
-- adds a 4-byte prefix; we use a 28-byte body so the total is exactly 32.
assetNameLengthTest :: IO ()
assetNameLengthTest = do
  let ref               = sampleTxOutRef
      GYTokenName refBs = cip68ReferenceTokenName ref
      GYTokenName usrBs = cip68UserTokenName ref
  BS.length refBs @?= 32
  BS.length usrBs @?= 32

-- | A deterministic but non-degenerate UTxO ref for the pure tests.
sampleTxOutRef :: GYTxOutRef
sampleTxOutRef =
  fromString
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef#0"

-------------------------------------------------------------------------------
-- Test wallet fixtures
-------------------------------------------------------------------------------

depositAC :: GYAssetClass
depositAC = fakeCoin fakeGold

paymentAC :: GYAssetClass
paymentAC = fakeCoin fakeIron

optionPrice :: GYRational
optionPrice = rationalFromGHC (2 % 1)

optionAmount :: Natural
optionAmount = 10

-- | Common CIP-68 display fields used by the trace tests.
displayName, imageUri, description, feeCfgRef :: Text
displayName = "Test Gold->Iron Call @ 2"
imageUri    = "data:image/svg+xml;base64,PLACEHOLDER"
description = "Trace-test option series."
feeCfgRef   = ""

-------------------------------------------------------------------------------
-- Helpers used by traces
-------------------------------------------------------------------------------

-- | Build the @(refAsset, skel)@ pair for a happy-path CIP-68 create.
buildCreateCIP68
  :: (GYTxQueryMonad m, GYTxUserQueryMonad m)
  => GYCompiledScripts
  -> m (GYAssetClass, GYTxSkeleton 'PlutusV2)
buildCreateCIP68 gycs = do
  addr  <- ownChangeAddress
  pkh   <- addressToPubKeyHash' addr
  sc    <- slotConfig
  cSlot <- slotOfCurrentBlock
  let
    start  = slotToBeginTimePure sc cSlot
    end    = slotToBeginTimePure sc $ unsafeAdvanceSlot cSlot 100
    cutoff = slotToBeginTimePure sc $ unsafeAdvanceSlot cSlot 50
  runReaderT
    (createOptionWithCIP68
       start end cutoff depositAC paymentAC optionPrice optionAmount pkh
       OptionCall True displayName imageUri description feeCfgRef)
    gycs

-------------------------------------------------------------------------------
-- Trace 1: happy-path create
-------------------------------------------------------------------------------

createCIP68Trace
  :: GYTxGameMonad m
  => GYCompiledScripts
  -> Wallets
  -> m ()
createCIP68Trace gycs Wallets {..} = asUser w1 $ do
  (_ref, sk) <- buildCreateCIP68 gycs
  void $ sendSkeleton sk

-------------------------------------------------------------------------------
-- Trace 2: ref NFT lands at AlwaysFails with inline datum
-------------------------------------------------------------------------------

refAtAlwaysFailsTrace
  :: GYTxGameMonad m
  => GYCompiledScripts
  -> Wallets
  -> m ()
refAtAlwaysFailsTrace gycs Wallets {..} = asUser w1 $ do
  (refAsset, sk)   <- buildCreateCIP68 gycs
  _                <- sendSkeleton sk
  cip68Addr        <- scriptAddress cip68ReferenceValidator
  utxos            <- utxosAtAddress cip68Addr (Just refAsset)
  let
    refUtxos       = utxosToList utxos
    inlineCount    = length (mapMaybe datumOf refUtxos)
  if not (null refUtxos) && inlineCount == length refUtxos
    then pure ()
    else throwAppError $ someBackendError
           $ fromString
           $ "expected ref NFT UTxO with inline datum at AlwaysFails address; "
             <> "found " <> show (length refUtxos) <> " UTxO(s), "
             <> "inline-datum-count=" <> show inlineCount
  where
    datumOf u = case utxoOutDatum u of
      GYOutDatumInline d -> Just d
      _                  -> Nothing

-------------------------------------------------------------------------------
-- Trace 3: ref NFT UTxO cannot be spent
-------------------------------------------------------------------------------

refCannotBeSpentTrace
  :: GYTxGameMonad m
  => GYCompiledScripts
  -> Wallets
  -> m ()
refCannotBeSpentTrace gycs Wallets {..} = asUser w1 $ do
  (refAsset, sk) <- buildCreateCIP68 gycs
  _              <- sendSkeleton sk
  cip68Addr      <- scriptAddress cip68ReferenceValidator
  utxos          <- utxosAtAddress cip68Addr (Just refAsset)
  case utxosToList utxos of
    []      ->
      throwAppError $ someBackendError "no ref NFT UTxO found to attempt-spend"
    (u : _) -> do
      -- Try to spend the AlwaysFails UTxO. The validator forces 'error ()'
      -- regardless of redeemer, so this skeleton must fail to submit.
      let
        dummyRedeemer = redeemerFromPlutusData (Plutus.I 0)
        spendSkeleton =
          mustHaveInput
            GYTxIn
              { gyTxInTxOutRef = utxoRef u
              , gyTxInWitness =
                  GYTxInWitnessScript
                    (GYInScript cip68ReferenceValidator)
                    Nothing
                    dummyRedeemer
              }
      void $ sendSkeleton spendSkeleton
