module Types.Value
  ( Coin(Coin)
  , CurrencySymbol(CurrencySymbol)
  , NonAdaAsset(NonAdaAsset)
  , TokenName(TokenName)
  , Value(Value)
  , adaSymbol
  , adaToken
  , allTokenNames
  , eq
  , flattenValue
  , fromValue
  , geq
  , getLovelace
  , gt
  , isAdaOnly
  , isPos
  , isZero
  , leq
  , lovelaceValueOf
  , lt
  , minus
  , numCurrencySymbols
  , numCurrencySymbols'
  , numTokenNames
  , numTokenNames'
  , toValue
  , valueOf
  ) where

import Prelude
import Control.Alternative (guard)
import Data.Array (filter)
import Data.BigInt (BigInt, fromInt)
import Data.Foldable (any, length)
import Data.Generic.Rep (class Generic)
import Data.List ((:), all, foldMap, List(Nil))
import Data.Map (keys, lookup, Map, toUnfoldable, unions, values)
import Data.Map as Map
import Data.Maybe (maybe, Maybe(Just, Nothing))
import Data.Newtype (class Newtype, unwrap, wrap)
import Data.Set (Set)
import Data.Show.Generic (genericShow)
import Data.These (These(Both, That, This))
import Data.Tuple.Nested ((/\), type (/\))

import Types.ByteArray (ByteArray)

-- Should we newtype wrap this over Ada or remove Ada completely.
newtype Coin = Coin BigInt

derive instance Generic Coin _
derive instance newtypeCoin :: Newtype Coin _
derive newtype instance eqCoin :: Eq Coin

instance Show Coin where
  show = genericShow

instance semigroupCoin :: Semigroup Coin where
  append (Coin c1) (Coin c2) = Coin (c1 + c2)

instance monoidCoin :: Monoid Coin where
  mempty = Coin zero

-- This module rewrites functionality from:
-- https://github.com/mlabs-haskell/bot-plutus-interface/blob/master/src/BotPlutusInterface/PreBalance.hs
-- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value

getLovelace :: Coin -> BigInt
getLovelace = unwrap

lovelaceValueOf :: BigInt -> Value
lovelaceValueOf = flip (Value <<< wrap) mempty

-- | Create a 'Value' containing only the given 'Coin/Ada'.
toValue :: Coin -> Value
toValue (Coin i) = lovelaceValueOf i

-- | Get the 'Coin/Ada' in the given 'Value'.
fromValue :: Value -> Coin
fromValue v = Coin (valueOf v adaSymbol adaToken)

newtype CurrencySymbol = CurrencySymbol ByteArray

derive instance newtypeCurrencySymbol :: Newtype CurrencySymbol _
derive instance genericCurrencySymbol :: Generic CurrencySymbol _
derive newtype instance eqCurrencySymbol :: Eq CurrencySymbol
derive newtype instance ordCurrencySymbol :: Ord CurrencySymbol

instance showCurrencySymbol :: Show CurrencySymbol where
  show = genericShow

newtype TokenName = TokenName ByteArray

derive instance newtypeTokenName :: Newtype TokenName _
derive instance genericTokenName :: Generic TokenName _
derive newtype instance eqTokenName :: Eq TokenName
derive newtype instance ordTokenName :: Ord TokenName

instance showTokenName :: Show TokenName where
  show = genericShow

newtype NonAdaAsset = NonAdaAsset (Map CurrencySymbol (Map TokenName BigInt))

derive instance newtypeNonAdaAsset :: Newtype NonAdaAsset _
derive instance genericNonAdaAsset :: Generic NonAdaAsset _
derive newtype instance eqNonAdaAsset :: Eq NonAdaAsset

instance showNonAdaAsset :: Show NonAdaAsset where
  show = genericShow

instance semigroupNonAdaAsset :: Semigroup NonAdaAsset where
  append = unionWith (+)

instance monoidNonAdaAsset :: Monoid NonAdaAsset where
  mempty = NonAdaAsset Map.empty

-- | In Plutus, Ada is is stored inside the map (with currency symbol and token
-- | name being empty bytestrings). cardano-serialization-lib makes semantic
-- | distinction between native tokens and Ada, and we follow this convention.
data Value = Value Coin NonAdaAsset

derive instance genericValue :: Generic Value _
derive instance eqValue :: Eq Value

instance showValue :: Show Value where
  show = genericShow

instance semigroupValue :: Semigroup Value where
  append (Value c1 m1) (Value c2 m2) = Value (c1 <> c2) (m1 <> m2)

instance monoidValue :: Monoid Value where
  mempty = Value mempty mempty

-- | Currency symbol for Ada, do not use inside NonAdaAsset map
adaSymbol :: CurrencySymbol
adaSymbol = CurrencySymbol mempty

-- | Token name for Ada, do not use inside NonAdaAsset map
adaToken :: TokenName
adaToken = TokenName mempty

-- https://playground.plutus.iohkdev.io/doc/haddock/plutus-tx/html/src/PlutusTx.AssocMap.html#union
-- | Combine two 'Map's.
union :: ∀ k v r. Ord k => Map k v -> Map k r -> Map k (These v r)
union l r =
  let
    ls :: Array (k /\ v)
    ls = Map.toUnfoldable l

    rs :: Array (k /\ r)
    rs = Map.toUnfoldable r

    f :: v -> Maybe r -> These v r
    f a b' = case b' of
      Nothing -> This a
      Just b -> Both a b

    ls' :: Array (k /\ These v r)
    ls' = map (\(c /\ i) -> (c /\ f i (Map.lookup c (Map.fromFoldable rs)))) ls

    rs' :: Array (k /\ r)
    rs' = filter (\(c /\ _) -> not (any (\(c' /\ _) -> c' == c) ls)) rs

    rs'' :: Array (k /\ These v r)
    rs'' = map (map That) rs'
  in
    Map.fromFoldable (ls' <> rs'')

-- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#unionVal
-- | Combine two 'NonAdaAsset' maps
unionNonAda
  :: NonAdaAsset
  -> NonAdaAsset
  -> Map CurrencySymbol (Map TokenName (These BigInt BigInt))
unionNonAda (NonAdaAsset l) (NonAdaAsset r) =
  let
    combined
      :: Map CurrencySymbol (These (Map TokenName BigInt) (Map TokenName BigInt))
    combined = union l r

    unBoth
      :: These (Map TokenName BigInt) (Map TokenName BigInt)
      -> Map TokenName (These BigInt BigInt)
    unBoth k = case k of
      This a -> This <$> a
      That b -> That <$> b
      Both a b -> union a b
  in
    unBoth <$> combined

-- -- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#unionVal
-- -- | Combine two 'Value' maps (variation to include Coin)
-- unionVal
--   :: Value
--   -> Value
--   -> These BigInt BigInt /\ Map CurrencySymbol (Map TokenName (These BigInt BigInt))
-- unionVal (Value cl l) (Value cr r) =
--   let combined
--         :: Map CurrencySymbol (These (Map TokenName BigInt) (Map TokenName BigInt))
--       combined = union l r
--       unBoth
--         :: These (Map TokenName BigInt) (Map TokenName BigInt)
--         -> Map TokenName (These BigInt BigInt)
--       unBoth k = case k of
--         This a -> This <$> a
--         That b -> That <$> b
--         Both a b -> union a b
--    in (Both <$> cl <*> cr) /\ (unBoth <$> combined)

-- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#unionWith
unionWith
  :: (BigInt -> BigInt -> BigInt)
  -> NonAdaAsset
  -> NonAdaAsset
  -> NonAdaAsset
unionWith f ls rs =
  let
    combined :: Map CurrencySymbol (Map TokenName (These BigInt BigInt))
    combined = unionNonAda ls rs

    unBoth :: These BigInt BigInt -> BigInt
    unBoth k' = case k' of
      This a -> f a zero
      That b -> f zero b
      Both a b -> f a b
  in
    NonAdaAsset $ map unBoth <$> combined

-- -- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#unionWith
-- unionWith
--   :: (BigInt -> BigInt -> BigInt)
--   -> Value
--   -> Value
--   -> Value
-- unionWith f ls rs =
--   let coin /\ nonAdaAsset = unionVal ls rs
--       unBoth :: These BigInt BigInt -> BigInt
--       unBoth k' = case k' of
--         This a -> f a zero
--         That b -> f zero b
--         Both a b -> f a b
--    in Value (unBoth <$> coin) (map (map unBoth) nonAdaAsset)

-- -- Could use Data.Newtype (unwrap) too.
-- getValue :: Value -> Map CurrencySymbol (Map TokenName BigInt)
-- getValue = unwrap

-- Based on https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#flattenValue
-- | Flattens non-Ada Value into a list
flattenNonAdaValue :: NonAdaAsset -> List (CurrencySymbol /\ TokenName /\ BigInt)
flattenNonAdaValue (NonAdaAsset nonAdaAsset) = do
  cs /\ m :: CurrencySymbol /\ (Map TokenName BigInt) <-
    toUnfoldable nonAdaAsset
  tn /\ a :: TokenName /\ BigInt <- toUnfoldable m
  guard $ a /= zero
  pure $ cs /\ tn /\ a

-- -- | Same as flattenNonAdaValue but for the entire Value
-- flattenNonAdaValue' :: Value -> List (CurrencySymbol /\ TokenName /\ BigInt)
-- flattenNonAdaValue' (Value _ nonAdaAsset) = flattenNonAdaValue nonAdaAsset

-- | Flattens Value guarding against zeros
flattenValue :: Value -> List (CurrencySymbol /\ TokenName /\ BigInt)
flattenValue (Value coin@(Coin lovelaces) nonAdaAsset) =
  let
    flattenedNonAda :: List (CurrencySymbol /\ TokenName /\ BigInt)
    flattenedNonAda = flattenNonAdaValue nonAdaAsset
  in
    case coin == mempty of
      true -> flattenedNonAda
      false -> (adaSymbol /\ adaToken /\ lovelaces) : flattenedNonAda

isAda :: CurrencySymbol -> TokenName -> Boolean
isAda curSymbol tokenName =
  curSymbol == adaSymbol &&
    tokenName == adaToken

-- From https://github.com/mlabs-haskell/bot-plutus-interface/blob/master/src/BotPlutusInterface/PreBalance.hs
-- | Converts a single tuple to Value
unflattenValue :: CurrencySymbol /\ TokenName /\ BigInt -> Value
unflattenValue (curSymbol /\ tokenName /\ amount) =
  case isAda curSymbol tokenName of
    false ->
      Value mempty
        <<< wrap
        <<< Map.singleton curSymbol
        <<<
          Map.singleton tokenName $ amount
    true -> Value (wrap amount) mempty

-- | Predicate on whether some Value contains Ada only.
isAdaOnly :: Value -> Boolean
isAdaOnly v =
  case flattenValue v of
    (cs /\ tn /\ _) : Nil ->
      cs == adaSymbol &&
        tn == adaToken
    _ -> false

-- From https://github.com/mlabs-haskell/bot-plutus-interface/blob/master/src/BotPlutusInterface/PreBalance.hs
minus :: Value -> Value -> Value
minus x y =
  let
    negativeValues :: List (CurrencySymbol /\ TokenName /\ BigInt)
    negativeValues = flattenValue y <#>
      (\(c /\ t /\ a) -> c /\ t /\ negate a)
  in
    x <> foldMap unflattenValue negativeValues

-- From https://github.com/mlabs-haskell/bot-plutus-interface/blob/master/src/BotPlutusInterface/PreBalance.hs
-- "isValueNat" uses flattenValue which guards against zeros, so non-strict
-- inequality is redundant. So we use strict equality instead.
isPos :: Value -> Boolean
isPos = all (\(_ /\ _ /\ a) -> a > zero) <<< flattenValue

-- From https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#isZero
-- | Check whether a 'Value' is zero.
isZero :: Value -> Boolean
isZero (Value coin (NonAdaAsset nonAdaAsset)) =
  all (all ((==) zero)) nonAdaAsset && coin == mempty

-- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#checkPred
checkPred :: (These BigInt BigInt -> Boolean) -> Value -> Value -> Boolean
checkPred f (Value (Coin l) ls) (Value (Coin r) rs) =
  let
    inner :: Map TokenName (These BigInt BigInt) -> Boolean
    inner = all f -- this "all" may need to be checked?
  in
    f (Both l r) && all inner (unionNonAda ls rs) -- this "all" may need to be checked?

-- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#checkBinRel
-- | Check whether a binary relation holds for value pairs of two 'Value' maps,
-- |  supplying 0 where a key is only present in one of them.
checkBinRel :: (BigInt -> BigInt -> Boolean) -> Value -> Value -> Boolean
checkBinRel f l r =
  let
    unThese :: These BigInt BigInt -> Boolean
    unThese k' = case k' of
      This a -> f a zero
      That b -> f zero b
      Both a b -> f a b
  in
    checkPred unThese l r

-- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#geq
-- | Check whether one 'Value' is greater than or equal to another. See 'Value' for an explanation of how operations on 'Value's work.
geq :: Value -> Value -> Boolean
-- If both are zero then checkBinRel will be vacuously true, but this is fine.
geq = checkBinRel (>=)

-- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#gt
-- | Check whether one 'Value' is strictly greater than another. See 'Value' for an explanation of how operations on 'Value's work.
gt :: Value -> Value -> Boolean
-- If both are zero then checkBinRel will be vacuously true. So we have a special case.
gt l r = not (isZero l && isZero r) && checkBinRel (>) l r

-- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#leq
-- | Check whether one 'Value' is less than or equal to another. See 'Value' for an explanation of how operations on 'Value's work.
leq :: Value -> Value -> Boolean
-- If both are zero then checkBinRel will be vacuously true, but this is fine.
leq = checkBinRel (<=)

-- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#lt
-- | Check whether one 'Value' is strictly less than another. See 'Value' for an explanation of how operations on 'Value's work.
lt :: Value -> Value -> Boolean
-- If both are zero then checkBinRel will be vacuously true. So we have a special case.
lt l r = not (isZero l && isZero r) && checkBinRel (<) l r

-- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#eq
-- | Check whether one 'Value' is equal to another. See 'Value' for an explanation of how operations on 'Value's work.
eq :: Value -> Value -> Boolean
-- If both are zero then checkBinRel will be vacuously true, but this is fine.
eq = checkBinRel (==)

-- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#valueOf
-- | Get the quantity of the given currency in the 'Value'.
valueOf :: Value -> CurrencySymbol -> TokenName -> BigInt
valueOf (Value coin nonAdaAsset) cur tn =
  case isAda cur tn of
    false ->
      case lookup cur (unwrap nonAdaAsset) of
        Nothing -> zero
        Just i -> case lookup tn i of
          Nothing -> zero
          Just v -> v
    true -> unwrap coin

-- -- https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/src/Plutus.V1.Ledger.Value.html#singleton
-- -- | Make a 'Value' containing only the given quantity of the given currency.
-- singleton :: CurrencySymbol -> TokenName -> BigInt -> Value
-- singleton curSymbol tokenName i =
--   case isAda curSymbol tokenName of
--     false ->
--       Value mempty (wrap $ Map.singleton curSymbol (Map.singleton tokenName i))
--     true ->
--       Value (wrap i) mempty

-- | The number of distinct currency symbols, i.e. the number of policy IDs.
numCurrencySymbols :: Value -> BigInt
numCurrencySymbols (Value coin nonAdaAsset) =
  case coin == mempty of
    false -> fromInt $ 1 + length (unwrap nonAdaAsset)
    true -> fromInt $ length (unwrap nonAdaAsset) -- FIX ME: Should we count this regardless whether it's zero?

numCurrencySymbols' :: Maybe Value -> BigInt
numCurrencySymbols' = maybe zero numCurrencySymbols

-- Don't export this, we don't really care about the v in k,v.
allTokenNames' :: Value -> Map TokenName BigInt
allTokenNames' (Value coin@(Coin lovelaces) (NonAdaAsset nonAdaAsset)) =
  let
    nonAdaUnion :: Map TokenName BigInt
    nonAdaUnion = unions $ values nonAdaAsset
  in
    case coin == mempty of
      false -> nonAdaUnion
      true -> Map.singleton adaToken lovelaces `Map.union` nonAdaUnion

allTokenNames :: Value -> Set TokenName
allTokenNames = keys <<< allTokenNames'

-- | The number of distinct token names.
numTokenNames :: Value -> BigInt
numTokenNames = length <<< allTokenNames'

numTokenNames' :: Maybe Value -> BigInt
numTokenNames' = maybe zero numTokenNames