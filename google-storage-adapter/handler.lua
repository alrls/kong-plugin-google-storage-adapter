local access = require "kong.plugins.google-storage-adapter.access"
local kong_meta = require "kong.meta"

local GoogleStorageAdapterHandler = {
  VERSION = kong_meta.version,
  PRIORITY = 901,
}

function GoogleStorageAdapterHandler:access(conf)
  access.execute(conf)
end

function GoogleStorageAdapterHandler:response(conf)
  local headers = kong.request.get_headers()
  for k,v in pairs(headers) do
    kong.log.notice(k .. v) 

  end
end

return GoogleStorageAdapterHandler