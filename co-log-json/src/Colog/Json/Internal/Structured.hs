{-# LANGUAGE UnliftedFFITypes #-}
{-# LANGUAGE MagicHash #-}
{-# OPTIONS_HADDOCK not-home #-}
-- |
--
-- Structure for tracing context.
--
-- We assume that each message ('Message') can be tagged with two types of values:
--
--    * @segment@ - path that tells where are we in the codebase.
--    * @attrbibutes@ - additional key-value tags, where value is an arbitrary json object.
-- 
-- Segment is needed in a case if we want to apply differrent logging rules to the differrent
-- parts of the codebase. For example we may way to log all the messages in the component one
-- but not all the rest.
--
-- In addition each @Message@ provides some common fields:
--
--    * "thread" - id of the thread that emits message
--    * "severity" - message severity
--
-- All messages in the same context share segment and attributes. So when exported to the log
-- analytics systems it's easy to load all the information associated with it.
--
-- **Compatibility note** internal structure of the message may be changed in the future in case
-- if it's proven that another implementation is faster or more memory efficient. However the
-- higher level API is likely to be stable.
module Colog.Json.Internal.Structured
  ( -- * Log datastructure.
    Structured(..)
  , Message(..)
  , LogStr(..)
  , PushContext(..)
    -- * Internals.
  , Severity(..)
  , encodeSeverity
  , showLS
  , ls
  , sl
  , mkThreadId
  ) where

import Control.Concurrent
import Data.Aeson
import Data.Aeson.Encoding as Aeson
import Data.Sequence
import Data.String
import Data.String.Conv
import qualified Data.Text as T
import qualified Data.Text.Lazy.Builder as TLB
import Foreign.C
import GHC.Conc
import GHC.Exts hiding (toList)

-- | Part of the structured message.
data Structured
  = Segment T.Text -- ^ Part of the message that is associated this the context of code.
  | Attr T.Text Encoding -- ^ Add attribute to the list.

-- | Log message.
data Message = Message
  { message_severity :: Severity -- ^ Message severity.
  , thread_id :: Int -- ^ Thread that emitted message.
  , attributes :: Seq Structured -- ^ List of attributes associated with the context.
  , message :: LogStr -- ^ Message to log.
  }


-- | Efficient message builder.
newtype LogStr = LogStr TLB.Builder
  deriving newtype IsString
  deriving newtype Semigroup
  deriving newtype Monoid

-- | Logger severity.
data Severity
  = DebugS      -- ^ Debug level, intended for internal information
  | InfoS       -- ^ Info level, that may be interesting to the user
  | NoticeS     -- ^ Notice, information that
  | WarningS    -- ^ Warning, information possible problem problem of some sort
  | ErrorS      -- ^ Error, information about a problem
  | CriticalS   -- ^ Critical error, intended for error that may break the system
  | AlertS      -- ^ Critical error where immediate actions should be taken
  | EmergencyS  -- ^ System wide emergency
  deriving (Show, Bounded, Eq, Ord, Enum)

-- | Convert severity into the one accepted by the loger.
encodeSeverity :: Severity -> Aeson.Encoding
{-# INLINE encodeSeverity #-}
encodeSeverity DebugS     = Aeson.text "DEBUG"
encodeSeverity InfoS      = Aeson.text "INFO"
encodeSeverity NoticeS    = Aeson.text "NOTICE"
encodeSeverity WarningS   = Aeson.text "WARNING"
encodeSeverity ErrorS     = Aeson.text "ERROR"
encodeSeverity CriticalS  = Aeson.text "CRITICAL"
encodeSeverity AlertS     = Aeson.text "ALERT"
encodeSeverity EmergencyS = Aeson.text "EMERGENCY"

-- | Wrapper over the structured message builder.
newtype PushContext = PushContext (Seq Structured -> Seq Structured)

-- | "Simple logger" adds a key value to the context:
--
-- @sl "foo" 123@
--
-- Will add @"foo":123@ key pair to the current list of the attributes.
-- Submitted value is stored with json encoding.
sl :: ToJSON a => T.Text -> a -> PushContext
sl label msg = PushContext \x ->
  x |> Attr label (toEncoding msg)

-- | Log any message.
logStr :: StringConv a T.Text => a -> LogStr
logStr t = LogStr (TLB.fromText $ toS t)

-- | Convert message can be converted.
ls :: StringConv a T.Text => a -> LogStr
ls = logStr

-- | Convert loggable value from any message that has show instance.
showLS :: Show a => a -> LogStr
showLS = ls . show

-- | Helper function to get id of the thread.
mkThreadId :: ThreadId -> Int
{-# NOINLINE mkThreadId #-}
mkThreadId (ThreadId tid) = fromIntegral (getThreadId tid)

foreign import ccall unsafe "rts_getThreadId" getThreadId :: ThreadId# -> CInt
