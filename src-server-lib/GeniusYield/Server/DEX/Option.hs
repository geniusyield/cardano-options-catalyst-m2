{-# LANGUAGE OverloadedLists #-}

module GeniusYield.Server.DEX.Option
  ( DEXOptionAPI
  , handleDEXOption
  )
where

import Control.Lens ((.~), (?~))
import Control.Monad.Reader (MonadIO (liftIO), MonadReader (ask))
import Data.Aeson qualified as Aeson
import Data.Map.Strict qualified as Map
import Data.Swagger qualified as Swagger
import Data.Swagger.Internal.Schema qualified as Swagger
import GeniusYield.Imports
import GeniusYield.TxBuilder.Class
import GeniusYield.Types
import Servant

import GeniusYield.Api.DEX.Option
  ( OptionInfo
  , cancelEarlyOption
  , createOption
  , createOptionWithCIP68
  , executeOption
  , optionAddress
  , optionInfos
  , retrieveOption
  )
import GeniusYield.Api.DEX.Option.CIP68 (OptionType)
import GeniusYield.Scripts.DEX.Option (cip68ReferenceValidator)
import GeniusYield.Server.Ctx
import GeniusYield.Server.SubmitResponse
import GeniusYield.Server.Utils

cancelCutoffTag, depositSymbolTag, depositTokenTag, paymentSymbolTag, paymentTokenTag, priceTag, refTag :: IsString p => p
cancelCutoffTag = "cancelCutoff"
depositSymbolTag = "depositSymbol"
depositTokenTag = "depositToken"
paymentSymbolTag = "paymentSymbol"
paymentTokenTag = "paymentToken"
priceTag = "price"
refTag = "ref"

optionTypeTag, cancellableTag, displayNameTag, imageUriTag, descriptionTag, feeCfgRefTag :: IsString p => p
optionTypeTag = "optionType"
cancellableTag = "cancellable"
displayNameTag = "displayName"
imageUriTag = "imageUri"
descriptionTag = "description"
feeCfgRefTag = "feeCfgRef"

type DexTxResponseGeneric =
  Task
    :& "tScriptAddress"
    =: GYAddress
    :& SubmitTxResponse

type DexTxResponseCreateOption = DexTxResponseGeneric

type DexTxResponseExecuteOption = DexTxResponseGeneric

type DexTxResponseRetrieveOption = DexTxResponseGeneric

data CreateOptionParams = CreateOptionParams
  { coUsedAddrs :: ![GYAddress]
  , coChangeAddr :: !GYAddress
  , coCollateral :: !CollateralField
  , coStart :: !GYTime
  , coEnd :: !GYTime
  , coCancelCutoff :: !GYTime
  , coDepositSymbol :: !Text
  , coDepositToken :: !Text
  , coPaymentSymbol :: !Text
  , coPaymentToken :: !Text
  , coPrice :: !GYRational
  , coAmount :: !Natural
  }
  deriving stock (Generic, Show)

instance FromJSON CreateOptionParams where
  parseJSON = Aeson.withObject "CreateOptionParams" $ \v ->
    CreateOptionParams
      <$> v Aeson..: usedAddrsTag
      <*> v Aeson..: changeAddrTag
      <*> v Aeson..:? collateralTag
      <*> v Aeson..: startTag
      <*> v Aeson..: endTag
      <*> v Aeson..: cancelCutoffTag
      <*> v Aeson..: depositSymbolTag
      <*> v Aeson..: depositTokenTag
      <*> v Aeson..: paymentSymbolTag
      <*> v Aeson..: paymentTokenTag
      <*> v Aeson..: priceTag
      <*> v Aeson..: amountTag

instance Swagger.ToSchema CreateOptionParams where
  declareNamedSchema _ = do
    gyAddrListSchema <- Swagger.declareSchemaRef @[GYAddress] Proxy
    gyAddrSchema <- Swagger.declareSchemaRef @GYAddress Proxy
    gyRationalSchema <- Swagger.declareSchemaRef @GYRational Proxy
    gyTimeSchema <- Swagger.declareSchemaRef @GYTime Proxy
    collateralSchema <- Swagger.declareSchemaRef @CollateralField Proxy
    naturalSchema <- Swagger.declareSchemaRef @Natural Proxy
    textSchema <- Swagger.declareSchemaRef @Text Proxy

    return
      $ Swagger.named "CreateOptionParams"
      $ mempty
        & Swagger.type_
        ?~ Swagger.SwaggerObject
          & Swagger.properties
        .~ [ (usedAddrsTag, gyAddrListSchema)
           , (changeAddrTag, gyAddrSchema)
           , (collateralTag, collateralSchema)
           , (startTag, gyTimeSchema)
           , (endTag, gyTimeSchema)
           , (cancelCutoffTag, gyTimeSchema)
           , (depositSymbolTag, textSchema)
           , (depositTokenTag, textSchema)
           , (paymentSymbolTag, textSchema)
           , (paymentTokenTag, textSchema)
           , (priceTag, gyRationalSchema)
           , (amountTag, naturalSchema)
           ]
          & Swagger.maxProperties
        ?~ 12
          & Swagger.minProperties
        ?~ 11

data CreateOptionWithCIP68Params = CreateOptionWithCIP68Params
  { cocUsedAddrs :: ![GYAddress]
  , cocChangeAddr :: !GYAddress
  , cocCollateral :: !CollateralField
  , cocStart :: !GYTime
  , cocEnd :: !GYTime
  , cocCancelCutoff :: !GYTime
  , cocDepositSymbol :: !Text
  , cocDepositToken :: !Text
  , cocPaymentSymbol :: !Text
  , cocPaymentToken :: !Text
  , cocPrice :: !GYRational
  , cocAmount :: !Natural
  , cocOptionType :: !OptionType
  , cocCancellable :: !Bool
  , cocDisplayName :: !Text
  , cocImageUri :: !Text
  , cocDescription :: !Text
  , cocFeeCfgRef :: !Text
  }
  deriving stock (Generic, Show)

instance FromJSON CreateOptionWithCIP68Params where
  parseJSON = Aeson.withObject "CreateOptionWithCIP68Params" $ \v ->
    CreateOptionWithCIP68Params
      <$> v Aeson..: usedAddrsTag
      <*> v Aeson..: changeAddrTag
      <*> v Aeson..:? collateralTag
      <*> v Aeson..: startTag
      <*> v Aeson..: endTag
      <*> v Aeson..: cancelCutoffTag
      <*> v Aeson..: depositSymbolTag
      <*> v Aeson..: depositTokenTag
      <*> v Aeson..: paymentSymbolTag
      <*> v Aeson..: paymentTokenTag
      <*> v Aeson..: priceTag
      <*> v Aeson..: amountTag
      <*> v Aeson..: optionTypeTag
      <*> v Aeson..: cancellableTag
      <*> v Aeson..: displayNameTag
      <*> v Aeson..: imageUriTag
      <*> v Aeson..: descriptionTag
      <*> v Aeson..: feeCfgRefTag

instance Swagger.ToSchema CreateOptionWithCIP68Params where
  declareNamedSchema _ = do
    gyAddrListSchema <- Swagger.declareSchemaRef @[GYAddress] Proxy
    gyAddrSchema <- Swagger.declareSchemaRef @GYAddress Proxy
    gyRationalSchema <- Swagger.declareSchemaRef @GYRational Proxy
    gyTimeSchema <- Swagger.declareSchemaRef @GYTime Proxy
    collateralSchema <- Swagger.declareSchemaRef @CollateralField Proxy
    naturalSchema <- Swagger.declareSchemaRef @Natural Proxy
    textSchema <- Swagger.declareSchemaRef @Text Proxy
    boolSchema <- Swagger.declareSchemaRef @Bool Proxy
    optionTypeSchema <- Swagger.declareSchemaRef @OptionType Proxy

    return
      $ Swagger.named "CreateOptionWithCIP68Params"
      $ mempty
        & Swagger.type_
        ?~ Swagger.SwaggerObject
          & Swagger.properties
        .~ [ (usedAddrsTag, gyAddrListSchema)
           , (changeAddrTag, gyAddrSchema)
           , (collateralTag, collateralSchema)
           , (startTag, gyTimeSchema)
           , (endTag, gyTimeSchema)
           , (cancelCutoffTag, gyTimeSchema)
           , (depositSymbolTag, textSchema)
           , (depositTokenTag, textSchema)
           , (paymentSymbolTag, textSchema)
           , (paymentTokenTag, textSchema)
           , (priceTag, gyRationalSchema)
           , (amountTag, naturalSchema)
           , (optionTypeTag, optionTypeSchema)
           , (cancellableTag, boolSchema)
           , (displayNameTag, textSchema)
           , (imageUriTag, textSchema)
           , (descriptionTag, textSchema)
           , (feeCfgRefTag, textSchema)
           ]
          & Swagger.maxProperties
        ?~ 18
          & Swagger.minProperties
        ?~ 17

data ExecuteOptionParams = ExecuteOptionParams
  { eoUsedAddrs :: ![GYAddress]
  , eoChangeAddr :: !GYAddress
  , eoCollateral :: !CollateralField
  , eoRef :: !GYTxOutRef
  , eoAmount :: !Natural
  }
  deriving stock (Generic, Show)

instance FromJSON ExecuteOptionParams where
  parseJSON = Aeson.withObject "ExecuteOptionParams" $ \v ->
    ExecuteOptionParams
      <$> v Aeson..: usedAddrsTag
      <*> v Aeson..: changeAddrTag
      <*> v Aeson..:? collateralTag
      <*> v Aeson..: refTag
      <*> v Aeson..: amountTag

instance Swagger.ToSchema ExecuteOptionParams where
  declareNamedSchema _ = do
    gyAddrListSchema <- Swagger.declareSchemaRef @[GYAddress] Proxy
    gyAddrSchema <- Swagger.declareSchemaRef @GYAddress Proxy
    collateralSchema <- Swagger.declareSchemaRef @CollateralField Proxy
    gyTxOutRefSchema <- Swagger.declareSchemaRef @GYTxOutRef Proxy
    naturalSchema <- Swagger.declareSchemaRef @Natural Proxy

    return
      $ Swagger.named "ExecuteOptionParams"
      $ mempty
        & Swagger.type_
        ?~ Swagger.SwaggerObject
          & Swagger.properties
        .~ [ (usedAddrsTag, gyAddrListSchema)
           , (changeAddrTag, gyAddrSchema)
           , (collateralTag, collateralSchema)
           , (refTag, gyTxOutRefSchema)
           , (amountTag, naturalSchema)
           ]
          & Swagger.maxProperties
        ?~ 5
          & Swagger.minProperties
        ?~ 4

data RetrieveOptionParams = RetrieveOptionParams
  { roUsedAddrs :: ![GYAddress]
  , roChangeAddr :: !GYAddress
  , roCollateral :: !CollateralField
  , roRef :: !GYTxOutRef
  }
  deriving stock (Generic, Show)

instance FromJSON RetrieveOptionParams where
  parseJSON = Aeson.withObject "RetrieveOptionParams" $ \v ->
    RetrieveOptionParams
      <$> v Aeson..: usedAddrsTag
      <*> v Aeson..: changeAddrTag
      <*> v Aeson..:? collateralTag
      <*> v Aeson..: refTag

instance Swagger.ToSchema RetrieveOptionParams where
  declareNamedSchema _ = do
    gyAddrListSchema <- Swagger.declareSchemaRef @[GYAddress] Proxy
    gyAddrSchema <- Swagger.declareSchemaRef @GYAddress Proxy
    collateralSchema <- Swagger.declareSchemaRef @CollateralField Proxy
    gyTxOutRefSchema <- Swagger.declareSchemaRef @GYTxOutRef Proxy

    return
      $ Swagger.named "RetrieveOptionParams"
      $ mempty
        & Swagger.type_
        ?~ Swagger.SwaggerObject
          & Swagger.properties
        .~ [ (usedAddrsTag, gyAddrListSchema)
           , (changeAddrTag, gyAddrSchema)
           , (collateralTag, collateralSchema)
           , (refTag, gyTxOutRefSchema)
           ]
          & Swagger.maxProperties
        ?~ 4
          & Swagger.minProperties
        ?~ 3

data CancelEarlyOptionParams = CancelEarlyOptionParams
  { ceUsedAddrs :: ![GYAddress]
  , ceChangeAddr :: !GYAddress
  , ceCollateral :: !CollateralField
  , ceRef :: !GYTxOutRef
  }
  deriving stock (Generic, Show)

instance FromJSON CancelEarlyOptionParams where
  parseJSON = Aeson.withObject "CancelEarlyOptionParams" $ \v ->
    CancelEarlyOptionParams
      <$> v Aeson..: usedAddrsTag
      <*> v Aeson..: changeAddrTag
      <*> v Aeson..:? collateralTag
      <*> v Aeson..: refTag

instance Swagger.ToSchema CancelEarlyOptionParams where
  declareNamedSchema _ = do
    gyAddrListSchema <- Swagger.declareSchemaRef @[GYAddress] Proxy
    gyAddrSchema <- Swagger.declareSchemaRef @GYAddress Proxy
    collateralSchema <- Swagger.declareSchemaRef @CollateralField Proxy
    gyTxOutRefSchema <- Swagger.declareSchemaRef @GYTxOutRef Proxy

    return
      $ Swagger.named "CancelEarlyOptionParams"
      $ mempty
        & Swagger.type_
        ?~ Swagger.SwaggerObject
          & Swagger.properties
        .~ [ (usedAddrsTag, gyAddrListSchema)
           , (changeAddrTag, gyAddrSchema)
           , (collateralTag, collateralSchema)
           , (refTag, gyTxOutRefSchema)
           ]
          & Swagger.maxProperties
        ?~ 4
          & Swagger.minProperties
        ?~ 3

type DexTxResponseCancelEarlyOption = DexTxResponseGeneric

type DexTxResponseCreateOptionWithCIP68 =
  Task
    :& "tScriptAddress"
    =: GYAddress
    :& "cip68ReferenceAddress"
    =: GYAddress
    :& "cip68ReferenceAsset"
    =: GYAssetClass
    :& SubmitTxResponse

type DEXOptionAPI =
  Get '[JSON] [OptionInfo]
    :<|> "create"
      :> ReqBody '[JSON] CreateOptionParams
      :> Post '[JSON] DexTxResponseCreateOption
    :<|> "create-cip68"
      :> ReqBody '[JSON] CreateOptionWithCIP68Params
      :> Post '[JSON] DexTxResponseCreateOptionWithCIP68
    :<|> "execute"
      :> ReqBody '[JSON] ExecuteOptionParams
      :> Post '[JSON] DexTxResponseExecuteOption
    :<|> "retrieve"
      :> ReqBody '[JSON] RetrieveOptionParams
      :> Post '[JSON] DexTxResponseRetrieveOption
    :<|> "cancel-early"
      :> ReqBody '[JSON] CancelEarlyOptionParams
      :> Post '[JSON] DexTxResponseCancelEarlyOption

handleDEXOption :: ServerT DEXOptionAPI ServerM
handleDEXOption =
  handleOptions
    :<|> handleCreateOption
    :<|> handleCreateOptionWithCIP68
    :<|> handleExecuteOption
    :<|> handleRetrieveOption
    :<|> handleCancelEarlyOption

handleOptions :: ServerM [OptionInfo]
handleOptions = do
  ctx <- ask
  liftIO $ Map.elems <$> runQuery ctx optionInfos

handleCreateOption :: CreateOptionParams -> ServerM DexTxResponseCreateOption
handleCreateOption CreateOptionParams {..} = do
  ctx <- ask
  liftIO $ do
    depositAC <- makeAssetClassIO coDepositSymbol coDepositToken
    paymentAC <- makeAssetClassIO coPaymentSymbol coPaymentToken
    pkh <- pubKeyFromAddress coChangeAddr
    txBody <-
      runSkeletonI ctx coUsedAddrs coChangeAddr coCollateral
        $ createOption
          coStart
          coEnd
          coCancelCutoff
          depositAC
          paymentAC
          coPrice
          coAmount
          pkh
    task <- returnUnsigned ctx txBody
    addr <- runQuery ctx optionAddress
    return $ task :& nprop addr :& txBodySubmitTxResponse txBody

handleCreateOptionWithCIP68 :: CreateOptionWithCIP68Params -> ServerM DexTxResponseCreateOptionWithCIP68
handleCreateOptionWithCIP68 CreateOptionWithCIP68Params {..} = do
  ctx <- ask
  liftIO $ do
    depositAC <- makeAssetClassIO cocDepositSymbol cocDepositToken
    paymentAC <- makeAssetClassIO cocPaymentSymbol cocPaymentToken
    pkh <- pubKeyFromAddress cocChangeAddr
    -- 'runSkeletonF' is 'Traversable t' polymorphic. Pairing the reference NFT
    -- asset class with the skeleton as @(refAsset, skel)@ lets us thread the
    -- asset class through the build via the @Traversable ((,) GYAssetClass)@
    -- instance, so the final result type is @(GYAssetClass, GYTxBody)@.
    (refAsset, txBody) <-
      runSkeletonF ctx cocUsedAddrs cocChangeAddr cocCollateral
        $ createOptionWithCIP68
          cocStart
          cocEnd
          cocCancelCutoff
          depositAC
          paymentAC
          cocPrice
          cocAmount
          pkh
          cocOptionType
          cocCancellable
          cocDisplayName
          cocImageUri
          cocDescription
          cocFeeCfgRef
    task <- returnUnsigned ctx txBody
    addr <- runQuery ctx optionAddress
    cip68Addr <- runQuery ctx (scriptAddress cip68ReferenceValidator)
    return
      $ task
        :& nprop addr
        :& nprop cip68Addr
        :& nprop refAsset
        :& txBodySubmitTxResponse txBody

handleExecuteOption :: ExecuteOptionParams -> ServerM DexTxResponseExecuteOption
handleExecuteOption ExecuteOptionParams {..} = do
  ctx <- ask
  liftIO $ do
    txBody <- runSkeletonI ctx eoUsedAddrs eoChangeAddr eoCollateral $ executeOption eoRef eoAmount
    task <- returnUnsigned ctx txBody
    addr <- runQuery ctx optionAddress
    return $ task :& nprop addr :& txBodySubmitTxResponse txBody

handleRetrieveOption :: RetrieveOptionParams -> ServerM DexTxResponseRetrieveOption
handleRetrieveOption RetrieveOptionParams {..} = do
  ctx <- ask
  liftIO $ do
    txBody <- runSkeletonI ctx roUsedAddrs roChangeAddr roCollateral $ retrieveOption roRef
    task <- returnUnsigned ctx txBody
    addr <- runQuery ctx optionAddress
    return $ task :& nprop addr :& txBodySubmitTxResponse txBody

handleCancelEarlyOption :: CancelEarlyOptionParams -> ServerM DexTxResponseCancelEarlyOption
handleCancelEarlyOption CancelEarlyOptionParams {..} = do
  ctx <- ask
  liftIO $ do
    txBody <- runSkeletonI ctx ceUsedAddrs ceChangeAddr ceCollateral $ cancelEarlyOption ceRef
    task <- returnUnsigned ctx txBody
    addr <- runQuery ctx optionAddress
    return $ task :& nprop addr :& txBodySubmitTxResponse txBody
