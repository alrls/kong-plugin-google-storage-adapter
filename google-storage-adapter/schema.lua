local typedefs = require "kong.db.schema.typedefs"

local PLUGIN_NAME = "google-storage-adapter"

return {
  name = PLUGIN_NAME,
  fields = {
    { protocols = typedefs.protocols { default = { "http", "https" } } },
    {
      config = {
        type = "record",
        fields = {
          {
            path_transformation = {
              type = "record",
              fields = {
                { enabled = { type = "boolean", required = true, default = true } },
                { log = { type = "boolean", required = true, default = false } },
                { prefix = { type = "string", required = false } }
              }
            }
          },
          {
            request_authentication = {
              type = "record",
              fields = {
                { enabled = { type = "boolean", required = true, default = true } },
                { log = { type = "boolean", required = true, default = false } },
                { bucket_name = { type = "string", required = true } },
                { access_id = { type = "string", required = true } },
                { secret = { type = "string", required = true } }
              }
            }
          },
          {
            service_headers = {
              type = "record",
              fields = {
                { enabled = { type = "boolean", required = true, default = true } },
                { log = { type = "boolean", required = true, default = false } }
              }
            }
          }
        }
      }
    }
  }
}
