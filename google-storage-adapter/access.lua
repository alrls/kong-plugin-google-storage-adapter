local openssl_hmac = require "resty.openssl.hmac"
local sha256 = require "resty.sha256"
local str = require "resty.string"

local get_path = kong.request.get_path
local get_raw_query = kong.request.get_raw_query
local set_path = kong.service.request.set_path
local set_header = kong.service.request.set_header

local kong = kong

local KONG_SITES_PREFIX = "/sites"

local GCLOUD_STORAGE_HOST = "storage.googleapis.com"
local GCLOUD_METHOD = 'GET'
local GCLOUD_SIGNING_ALGORITHM = 'GOOG4-HMAC-SHA256'
local GCLOUD_REGION = "auto"
local GCLOUD_SERVICE = 'storage'
local GCLOUD_REQUEST_TYPE = 'goog4_request'
local GCLOUD_SIGNED_HEADERS = 'host;x-goog-content-sha256;x-goog-date'
local GCLOUD_UNSIGNED_PAYLOAD = 'UNSIGNED-PAYLOAD'

local _M = {}

local function get_normalized_path()
  local path = get_path()
  if string.match(path, "(.*)/$") then
    return path .. "index.html"
  elseif string.match(path, "(.*)/[^/.]+$") then
    return path .. "/index.html"
  end
  return path
end

local function transform_uri(conf)
  if not conf.path_transformation.enable then
    return
  end

  set_path(get_normalized_path())
end

local function create_canonical_request(bucket_name, current_precise_date)
  local host = bucket_name .. "." .. GCLOUD_STORAGE_HOST

  local path = get_normalized_path();
  kong.log.notice("Path " .. path)
  local query_string = get_raw_query()

  local canonical_uri = path:gsub(KONG_SITES_PREFIX, "")
  local canonical_headers = 'host:' .. host .. "\n" ..
      'x-goog-content-sha256:' .. GCLOUD_UNSIGNED_PAYLOAD .. "\n" ..
      'x-goog-date:' .. current_precise_date

  local canonical_request = GCLOUD_METHOD .. "\n" ..
      canonical_uri .. "\n" ..
      query_string .. "\n" ..
      canonical_headers .. '\n\n' ..
      GCLOUD_SIGNED_HEADERS .. "\n" ..
      GCLOUD_UNSIGNED_PAYLOAD

  local digest = sha256:new()
  digest:update(canonical_request)
  local canonical_request_hex = str.to_hex(digest:final())
  return canonical_request_hex
end

local function create_signing_key(secret, current_date)
  local secret = "GOOG4" .. secret
  local key_date = openssl_hmac.new(secret, "sha256"):final(current_date)
  local key_region = openssl_hmac.new(key_date, "sha256"):final(GCLOUD_REGION)
  local key_service = openssl_hmac.new(key_region, "sha256"):final(GCLOUD_SERVICE)
  local signing_key = openssl_hmac.new(key_service, "sha256"):final(GCLOUD_REQUEST_TYPE)
  return signing_key
end

-- implementation from https://cloud.google.com/storage/docs/authentication/signatures
local function do_authentication(conf)
  if not conf.request_authentication.enable then
    return
  end

  local current_date = os.date("%Y%m%d")                 -- YYYYMMDD
  local current_precise_date = os.date("%Y%m%dT%H%M%SZ") -- YYYYMMDD'T'HHMMSS'Z'

  local credential_scope = current_date .. "/" .. GCLOUD_REGION .. "/" .. GCLOUD_SERVICE .. "/" .. GCLOUD_REQUEST_TYPE

  local canonical_request_hex = create_canonical_request(conf.request_authentication.bucket_name, current_precise_date)
  local string_to_sign = GCLOUD_SIGNING_ALGORITHM .. "\n" ..
      current_precise_date .. "\n" ..
      credential_scope .. "\n" ..
      canonical_request_hex

  local signing_key = create_signing_key(conf.request_authentication.secret, current_date)
  local signature_raw = openssl_hmac.new(signing_key, "sha256"):final(string_to_sign)
  local signature_hex = str.to_hex(signature_raw)
  kong.log.notice("The signature has been created" .. signature_hex .. "with date" .. current_precise_date)

  local credential = conf.request_authentication.access_id .. "/" .. credential_scope
  local auth_header = GCLOUD_SIGNING_ALGORITHM .. " " ..
      "Credential=" .. credential ..
      ", SignedHeaders=" .. GCLOUD_SIGNED_HEADERS ..
      ", Signature=" .. signature_hex

  set_header("authorization", auth_header)
  set_header("x-goog-date", current_precise_date)
  set_header("x-goog-content-sha256", GCLOUD_UNSIGNED_PAYLOAD)
end

function _M.execute(conf)
  transform_uri(conf)
  do_authentication(conf)
end

return _M
