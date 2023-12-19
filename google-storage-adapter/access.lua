local openssl_hmac = require "resty.openssl.hmac"
local sha256 = require "resty.sha256"
local str = require "resty.string"

local get_req_path = kong.request.get_path
local get_raw_query = kong.request.get_raw_query
local get_service = kong.router.get_service
local set_path = kong.service.request.set_path
local set_header = kong.service.request.set_header

local kong = kong

local GCLOUD_STORAGE_HOST = "storage.googleapis.com"
local GCLOUD_METHOD = 'GET'
local GCLOUD_SIGNING_ALGORITHM = 'GOOG4-HMAC-SHA256'
local GCLOUD_REGION = "auto"
local GCLOUD_SERVICE = 'storage'
local GCLOUD_REQUEST_TYPE = 'goog4_request'
local GCLOUD_SIGNED_HEADERS = 'host;x-goog-content-sha256;x-goog-date'
local GCLOUD_UNSIGNED_PAYLOAD = 'UNSIGNED-PAYLOAD'

local _M = {}

local function get_service_path()
  local service = get_service()
  if service then
    return service.path
  end
  return ""
end

local function get_normalized_path(conf)
  local service_path = get_service_path()
  -- if there's any override to a particular page (e.g. 403.html)
  if string.match(service_path, "(.*).html$") then
    return service_path
  end

  local req_path = get_req_path()
  -- we have to remove prefix anyway
  req_path = string.gsub(req_path, conf.path_transformation.prefix, "") 

  if not conf.path_transformation.enabled then
    return req_path
  end

  -- handle case when we have a trailing slash in the end of the path
  if string.match(req_path, "(.*)/$") then
    return req_path .. "index.html"
  end
  return req_path
end

local function create_canonical_request(conf, current_precise_date)
  local path = get_normalized_path(conf)

  local bucket_name = conf.request_authentication.bucket_name
  local host = bucket_name .. "." .. GCLOUD_STORAGE_HOST
  local query_string = get_raw_query()

  local canonical_uri = path
  local canonical_headers = 'host:' .. host .. "\n" ..
    'x-goog-content-sha256:' .. GCLOUD_UNSIGNED_PAYLOAD .. "\n" ..
    'x-goog-date:' .. current_precise_date

  local canonical_request = GCLOUD_METHOD .. "\n" ..
    canonical_uri .. "\n" ..
    query_string .. "\n" ..
    canonical_headers .. '\n\n' ..
    GCLOUD_SIGNED_HEADERS .. "\n" ..
    GCLOUD_UNSIGNED_PAYLOAD
  
  return canonical_request
end

local function create_hex_canonical_request(canonical_request) 
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
  if not conf.request_authentication.enabled then
    return
  end

  local current_date = os.date("%Y%m%d")                 -- YYYYMMDD
  local current_precise_date = os.date("%Y%m%dT%H%M%SZ") -- YYYYMMDD'T'HHMMSS'Z'

  local credential_scope = current_date .. "/" .. GCLOUD_REGION .. "/" .. GCLOUD_SERVICE .. "/" .. GCLOUD_REQUEST_TYPE

  local canonical_request = create_canonical_request(conf, current_precise_date)
  local canonical_request_hex = create_hex_canonical_request(canonical_request)
  local string_to_sign = GCLOUD_SIGNING_ALGORITHM .. "\n" ..
    current_precise_date .. "\n" ..
    credential_scope .. "\n" ..
    canonical_request_hex

  local signing_key = create_signing_key(conf.request_authentication.secret, current_date)
  local signature_raw = openssl_hmac.new(signing_key, "sha256"):final(string_to_sign)
  local signature_hex = str.to_hex(signature_raw)

  if conf.request_authentication.log then 
    local log_message = "The signature has been created " .. signature_hex .. 
      " with date " .. current_precise_date .. 
      " for the request " .. canonical_request
    kong.log.notice(log_message)
  end 

  local credential = conf.request_authentication.access_id .. "/" .. credential_scope
  local auth_header = GCLOUD_SIGNING_ALGORITHM .. " " ..
    "Credential=" .. credential ..
    ", SignedHeaders=" .. GCLOUD_SIGNED_HEADERS ..
    ", Signature=" .. signature_hex

  set_header("authorization", auth_header)
  set_header("x-goog-date", current_precise_date)
  set_header("x-goog-content-sha256", GCLOUD_UNSIGNED_PAYLOAD)
end

local function transform_uri(conf)
  if not conf.path_transformation.enabled then
    return
  end

  local service_path = get_service_path()
  local req_path = get_req_path()
  local normalized_path = get_normalized_path(conf)
  if conf.path_transformation.log then
    local log_message = "The upstream path may be modifed. The request path " .. req_path .. 
      ", the service path " .. service_path .. 
      ", the normalized path " .. normalized_path
    kong.log.notice(log_message)
  end

  set_path(normalized_path)
end

function _M.execute(conf)
  do_authentication(conf)
  transform_uri(conf)
end

return _M
