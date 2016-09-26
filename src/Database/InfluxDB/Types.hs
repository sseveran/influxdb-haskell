{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Database.InfluxDB.Types where
import Control.Exception
import Data.Data (Data)
import Data.Int (Int64)
import Data.String
import Data.Typeable (Typeable)
import GHC.Generics (Generic)

import Control.Lens
import Data.Text (Text)
import Data.Time.Clock
import Data.Time.Clock.POSIX
import Network.HTTP.Client (Manager, ManagerSettings, Request)
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T

newtype Query = Query T.Text deriving IsString

instance Show Query where
  show (Query q) = show q

data Server = Server
  { _host :: !Text
  , _port :: !Int
  , _ssl :: !Bool
  } deriving (Show, Generic)

localServer :: Server
localServer = Server
  { _host = "localhost"
  , _port = 8086
  , _ssl = False
  }

makeLenses ''Server

-- | User credentials
data Credentials = Credentials
  { _user :: !Text
  , _password :: !Text
  }

makeLenses ''Credentials

-- | Database name
newtype Database = Database { databaseName :: Text } deriving (Eq, Ord)

newtype RetentionPolicy = RetentionPolicy Text

-- | String type that is used for measurements, tag keys and field keys.
newtype Key = Key Text deriving (Eq, Ord)

instance IsString Database where
  fromString xs = Database $ fromNonEmptyString "Database" xs

instance IsString Key where
  fromString xs = Key $ fromNonEmptyString "Key" xs

fromNonEmptyString :: String -> String -> Text
fromNonEmptyString ty xs
  | null xs = error $ ty ++ " should never be empty"
  | otherwise = fromString xs

instance Show Database where
  show (Database name) = show name

instance Show Key where
  show (Key name) = show name

data FieldValue
  = FieldInt !Int64
  | FieldFloat !Double
  | FieldString !Text
  | FieldBool !Bool
  | FieldNull
  deriving (Eq, Show, Data, Typeable, Generic)

instance IsString FieldValue where
  fromString = FieldString . T.pack

-- | Type of a request
data RequestType
  = QueryRequest
  -- ^ Request for @/query@
  | WriteRequest
  -- ^ Request for @/write@

-- | Predefined set of time precision.
--
-- 'RFC3339' is only available for 'QueryRequest's.
data Precision (ty :: RequestType) where
  -- | POSIX time in ns
  Nanosecond :: Precision ty
  -- | POSIX time in μs
  Microsecond :: Precision ty
  -- | POSIX time in ms
  Millisecond :: Precision ty
  -- | POSIX time in s
  Second :: Precision ty
  -- | POSIX time in minutes
  Minute :: Precision ty
  -- | POSIX time in hours
  Hour :: Precision ty
  -- | Nanosecond precision time in a human readable format, like
  -- @2016-01-04T00:00:23.135623Z@. This is the default format for @/query@.
  RFC3339 :: Precision 'QueryRequest

precisionName :: Precision ty -> Text
precisionName = \case
  Nanosecond -> "n"
  Microsecond -> "u"
  Millisecond -> "ms"
  Second -> "s"
  Minute -> "m"
  Hour -> "h"
  RFC3339 -> "rfc3339"

-- | A 'Timestamp' is something that can be converted to a valid
-- InfluxDB timestamp, which is represented as a 64-bit integer.
class Timestamp time where
  -- | Round a time to the given precision and scale it to nanoseconds
  roundTo :: Precision 'WriteRequest -> time -> Int64
  -- | Scale a time to the given precision
  scaleTo :: Precision 'WriteRequest -> time -> Int64

roundAt :: RealFrac a => a -> a -> a
roundAt scale x = fromIntegral (round (x / scale) :: Int) * scale

precisionScale :: Fractional a => Precision ty -> a
precisionScale = \case
  RFC3339 ->     10^^(-9 :: Int)
  Nanosecond ->  10^^(-9 :: Int)
  Microsecond -> 10^^(-6 :: Int)
  Millisecond -> 10^^(-3 :: Int)
  Second -> 1
  Minute -> 60
  Hour ->   60 * 60

instance Timestamp UTCTime where
  roundTo prec = roundTo prec . utcTimeToPOSIXSeconds
  scaleTo prec = scaleTo prec . utcTimeToPOSIXSeconds

instance Timestamp NominalDiffTime where
  roundTo prec time =
    round $ 10^(9 :: Int) * roundAt (precisionScale prec) time
  scaleTo prec time = round $ time / precisionScale prec

data InfluxException
  = ServerError String
  | BadRequest String Request
  | IllformedJSON String BL.ByteString
  deriving (Show, Typeable)

instance Exception InfluxException

class HasServer a where
  server :: Lens' a Server

class HasDatabase a where
  database :: Lens' a Database

class HasPrecision (ty :: RequestType) a | a -> ty where
  precision :: Lens' a (Precision ty)

class HasManager a where
  manager :: Lens' a (Either ManagerSettings Manager)
