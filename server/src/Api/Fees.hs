module Api.Fees (estimateTxFees) where

import Cardano.Api qualified as C
import Cardano.Api.Shelley qualified as Shelley
import Control.Monad.Catch (throwM)
import Control.Monad.Reader (asks)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString.Base16 qualified as Base16
import Data.Proxy (Proxy (Proxy))
import Data.Text (Text)
import Data.Text.Encoding qualified as Text.Encoding
import Types (
  AppM,
  CardanoBrowserServerError (..),
  Cbor (..),
  Env (..),
  Fee (..),
  FeeEstimateError (..),
 )

estimateTxFees :: Cbor -> AppM Fee
estimateTxFees cbor = do
  decoded <- either (throwM . FeeEstimate) pure $ decodeCborTx cbor
  pparams <- asks protocolParams
  pure . Fee $ estimateFee pparams decoded

estimateFee :: Shelley.ProtocolParameters -> C.Tx C.AlonzoEra -> Integer
estimateFee pparams (C.Tx txBody keyWits) = estimate
  where
    estimate :: Integer
    C.Lovelace estimate =
      let -- No. of Shelley key witnesses
          numWits = fromIntegral $ length keyWits
       in C.evaluateTransactionFee
            pparams
            txBody
            numWits
            -- No. of Byron key witnesses; there shouldn't be any of these and
            -- 'evaluateTransactionFee' won't work with them anyway
            0

decodeCborTx :: Cbor -> Either FeeEstimateError (C.Tx C.AlonzoEra)
decodeCborTx (Cbor txt) =
  first InvalidCbor
    . C.deserialiseFromCBOR (C.proxyToAsType Proxy)
    =<< decode txt
  where
    decode :: Text -> Either FeeEstimateError ByteString
    decode = first InvalidHex . Base16.decode . Text.Encoding.encodeUtf8
