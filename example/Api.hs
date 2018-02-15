{-# LANGUAGE DeriveGeneric             #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE RankNTypes                #-}
{-# LANGUAGE RecordWildCards           #-}

module Api where

import           Data.Aeson
import           Data.Aeson.Types
import           Data.Bifunctor
import           Data.ByteString                   (ByteString)
import qualified Data.Text.Encoding                as TE
import           Data.Text.Lazy                    (Text)
import qualified Data.Text.Lazy                    as TL
import           GHC.Generics
import           Lens.Micro
import           Network.HTTP.Conduit
import           Network.OAuth.OAuth2
import qualified Network.OAuth.OAuth2.TokenRequest as TR
import           URI.ByteString

import qualified IDP.Douban                        as IDouban
import qualified IDP.Dropbox                       as IDropbox
import qualified IDP.Facebook                      as IFacebook
import qualified IDP.Fitbit                        as IFitbit
import qualified IDP.Github                        as IGithub
import qualified IDP.Google                        as IGoogle
import qualified IDP.Linkedin                      as ILinkedin
import qualified IDP.Okta                          as IOkta
import qualified IDP.StackExchange                 as IStackExchange
import qualified IDP.Weibo                         as IWeibo
import           Keys
import           Types

data Errors =
  SomeRandomError
  deriving (Show, Eq, Generic)

instance FromJSON Errors where
  parseJSON = genericParseJSON defaultOptions { constructorTagModifier = camelTo2 '_', allNullaryToStringTag = True }

createCodeUri :: OAuth2
              -> [(ByteString, ByteString)]
              -> Text
createCodeUri key params = TL.fromStrict $ TE.decodeUtf8 $ serializeURIRef'
  $ appendQueryParams params
  $ authorizationUrl key

mkIDPData :: IDP -> IDPData
mkIDPData Okta =
  let userUri = createCodeUri oktaKey [("scope", "openid profile"), ("state", "okta.test-state-123")]
  in
  IDPData { codeFlowUri = userUri
          , loginUser = Nothing
          , idpName = Okta
          , oauth2Key = oktaKey
          , toFetchAccessToken = getAT
          , userApiUri = IOkta.userInfoUri
          , toLoginUser = IOkta.toLoginUser
          }
mkIDPData Douban =
  let userUri = createCodeUri doubanKey [("state", "douban.test-state-123")]
  in
  IDPData { codeFlowUri = userUri
          , loginUser = Nothing
          , idpName = Douban
          , oauth2Key = doubanKey
          , toFetchAccessToken = postAT
          , userApiUri = IDouban.userInfoUri
          , toLoginUser = IDouban.toLoginUser
          }
mkIDPData Dropbox =
  let userUri = createCodeUri dropboxKey [("state", "dropbox.test-state-123")]
  in
  IDPData { codeFlowUri = userUri
          , loginUser = Nothing
          , idpName = Dropbox
          , oauth2Key = dropboxKey
          , toFetchAccessToken = getAT
          , userApiUri = IDropbox.userInfoUri
          , toLoginUser = IDropbox.toLoginUser
          }
mkIDPData Facebook =
  let userUri = createCodeUri facebookKey [ ("state", "facebook.test-state-123")
                                            , ("scope", "user_about_me,email")
                                            ]
  in
  IDPData { codeFlowUri = userUri
          , loginUser = Nothing
          , idpName = Facebook
          , oauth2Key = facebookKey
          , toFetchAccessToken = postAT
          , userApiUri = IFacebook.userInfoUri
          , toLoginUser = IFacebook.toLoginUser
          }
mkIDPData Fitbit =
  let userUri = createCodeUri fitbitKey [("state", "fitbit.test-state-123")
                                    , ("scope", "profile")
                                    ]
  in
  IDPData { codeFlowUri = userUri
          , loginUser = Nothing
          , idpName = Fitbit
          , oauth2Key = fitbitKey
          , toFetchAccessToken = getAT
          , userApiUri = IFitbit.userInfoUri
          , toLoginUser = IFitbit.toLoginUser
          }

mkIDPData Github =
  let userUri = createCodeUri githubKey [("state", "github.test-state-123")]
  in
  IDPData { codeFlowUri = userUri
          , loginUser = Nothing
          , idpName = Github
          , oauth2Key = githubKey
          , toFetchAccessToken = getAT
          , userApiUri = IGithub.userInfoUri
          , toLoginUser = IGithub.toLoginUser
          }
mkIDPData Google =
  let userUri = createCodeUri googleKey [ ("scope", "https://www.googleapis.com/auth/userinfo.email")
                                    , ("state", "google.test-state-123")
                                    ]
  in
  IDPData { codeFlowUri = userUri
          , loginUser = Nothing
          , idpName = Google
          , oauth2Key = googleKey
          , toFetchAccessToken = getAT
          , userApiUri = IGoogle.userInfoUri
          , toLoginUser = IGoogle.toLoginUser
          }
mkIDPData StackExchange =
  let userUri = createCodeUri stackexchangeKey [("state", "stackexchange.test-state-123")]
  in
  IDPData { codeFlowUri = userUri
          , loginUser = Nothing
          , idpName = StackExchange
          , oauth2Key = stackexchangeKey
          , toFetchAccessToken = postAT
          , userApiUri = IStackExchange.userInfoUri
          , toLoginUser = IStackExchange.toLoginUser
          }
mkIDPData Weibo =
  let userUri = createCodeUri weiboKey [("state", "weibo.test-state-123")]
  in
  IDPData { codeFlowUri = userUri
          , loginUser = Nothing
          , idpName = Weibo
          , oauth2Key = weiboKey
          , toFetchAccessToken = getAT
          , userApiUri = IWeibo.userInfoUri
          , toLoginUser = IWeibo.toLoginUser
          }

mkIDPData Linkedin =
  let userUri = createCodeUri linkedinKey [("state", "linkedin.test-state-123")]
  in
  IDPData { codeFlowUri = userUri
          , loginUser = Nothing
          , idpName = Linkedin
          , oauth2Key = linkedinKey
          , toFetchAccessToken = postAT
          , userApiUri = ILinkedin.userInfoUri
          , toLoginUser = ILinkedin.toLoginUser
          }

-- * Fetch UserInfo
--
getUserInfo :: IDPData -> Manager -> AccessToken -> IO (Either Text LoginUser)
getUserInfo idpD mgr token =
  case idpName idpD of
    Dropbox       -> getUserWithAccessTokenInHeaderOnly idpD mgr token
    Weibo         -> getUserWithAccessTokenAsParam idpD mgr token
    StackExchange -> getStackExchangeUser idpD mgr token
    _             -> getUserInfoInteral idpD mgr token

getUserInfoInteral :: IDPData -> Manager -> AccessToken -> IO (Either Text LoginUser)
getUserInfoInteral IDPData {..} mgr token = do
  re <- authGetJSON mgr token userApiUri
  return (bimap showGetError toLoginUser re)

showGetError :: OAuth2Error Errors -> Text
showGetError = TL.pack . show

getUserWithAccessTokenInHeaderOnly, getUserWithAccessTokenAsParam, getStackExchangeUser :: IDPData
  -> Manager
  -> AccessToken
  -> IO (Either Text LoginUser)

-- fetch user info via
-- POST
-- set token in header only
-- nothing for body
getUserWithAccessTokenInHeaderOnly IDPData {..} mgr token = do
  re <- parseResponseJSON <$> authPostBS3 mgr token userApiUri
  return (bimap showGetError toLoginUser re)

-- fetch user info via
-- GET
-- access token in query param only
getUserWithAccessTokenAsParam IDPData {..} mgr token = do
  re <- parseResponseJSON <$> authGetBS2 mgr token userApiUri
  return (bimap showGetError toLoginUser re)

-- fetch user info via
-- GET
-- access token in query param only
-- append extra application key
getStackExchangeUser IDPData {..} mgr token = do
  re <- parseResponseJSON
        <$> authGetBS2 mgr token
            (userApiUri `appendStackExchangeAppKey` stackexchangeAppKey)
  return (bimap showGetError toLoginUser re)

appendStackExchangeAppKey :: URI -> ByteString -> URI
appendStackExchangeAppKey uri k =
  over (queryL . queryPairsL) (\query -> query ++ [("key", k)]) uri

-- * Fetch Access Token
--
tryFetchAT :: IDPData
  -> Manager
  -> ExchangeToken
  -> IO (OAuth2Result TR.Errors OAuth2Token)
tryFetchAT IDPData {..} mgr = toFetchAccessToken mgr oauth2Key

getAT, postAT:: Manager
  -> OAuth2
  -> ExchangeToken
  -> IO (OAuth2Result TR.Errors OAuth2Token)
getAT = fetchAccessToken
postAT = postATX doJSONPostRequest

postATX :: (Manager -> OAuth2 -> URI -> PostBody -> IO (OAuth2Result TR.Errors OAuth2Token))
        -> Manager
        -> OAuth2
        -> ExchangeToken
        -> IO (OAuth2Result TR.Errors OAuth2Token)
postATX postFn mgr okey code = do
  let (url, body1) = accessTokenUrl okey code
  let extraBody = authClientBody okey
  postFn mgr okey url (extraBody ++ body1)

authClientBody :: OAuth2 -> [(ByteString, ByteString)]
authClientBody okey = [ ("client_id", TE.encodeUtf8 $ oauthClientId okey)
                      , ("client_secret", TE.encodeUtf8 $ oauthClientSecret okey)
                      ]
