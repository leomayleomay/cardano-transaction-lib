-- | This module tests that `awaitTxConfirmedWithTimeout` is actually
-- | interrupted after the given timeout elapses. To do that, it awaits
-- | a fake TX id that will never succeed and catches the resulting exception
-- | when the timeout elapses.
module Examples.AwaitTxConfirmedWithTimeout
  ( contract
  , main
  , example
  ) where

import Contract.Prelude

import Contract.Config (ConfigParams, testnetNamiConfig)
import Contract.Log (logInfo')
import Contract.Monad (Contract, launchAff_, runContract, throwContractError)
import Control.Monad.Error.Class (try)
import Contract.Test.E2E (publishTestFeedback)
import Contract.Transaction (awaitTxConfirmedWithTimeout)
import Types.Transaction (TransactionHash(TransactionHash))
import Types.ByteArray (hexToByteArrayUnsafe)

main :: Effect Unit
main = example testnetNamiConfig

example :: ConfigParams () -> Effect Unit
example cfg = launchAff_ do
  runContract cfg contract
  publishTestFeedback true

contract :: Contract () Unit
contract = do
  logInfo' "Running AwaitTxConfirmedWithTimeout"
  let
    fakeHash = TransactionHash $ hexToByteArrayUnsafe
      "ffffffffffff55555555555555555555a1af1b7534b51e60fad3fe9c164313e8"
  result <- try $ awaitTxConfirmedWithTimeout (wrap 1.0) fakeHash
  case result of
    Left _ -> pure unit
    Right _ -> throwContractError "expected awaitTxConfirmedWithTimeOut to fail"
