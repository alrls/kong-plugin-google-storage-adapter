local access = require "kong.plugins.google-storage-adapter.access"
local kong_meta = require "kong.meta"

local GoogleStorageAdapterHandler = {
  VERSION = kong_meta.version,
  PRIORITY = 901,
}

function GoogleStorageAdapterHandler:access(conf)
  access.execute(conf)
end

return GoogleStorageAdapterHandler