# Installation
http://luarocks.org/modules/newage/kong-plugin-google-storage-adapter

`luarocks install kong-plugin-google-storage-adapter`

```
custom_plugins = google-storage-adapter
```

`Reminder: don't forget to update the custom_plugins directive for each node in your Kong cluster.`

# API

POST :8001/plugins
```
{
	"name": "google-storage-adapter"
}
```
