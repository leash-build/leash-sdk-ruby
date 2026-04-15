# Leash SDK for Ruby

Ruby SDK for Leash-hosted integrations.

Use it to call Gmail, Google Calendar, Google Drive, and custom provider actions through the Leash platform proxy.

## Installation

```ruby
gem "leash-sdk"
```

or:

```bash
gem install leash-sdk
```

## Quick Start

```ruby
require "leash"

client = Leash::Integrations.new(
  auth_token: ENV["LEASH_AUTH_TOKEN"],
  api_key: ENV["LEASH_API_KEY"]
)

if client.connected?("gmail")
  messages = client.gmail.list_messages(max_results: 5)
  puts messages
else
  puts client.connect_url("gmail", return_url: "https://myapp.example.com/settings")
end
```

## Default Platform URL

- `https://leash.build`

## Features

- Gmail
- Google Calendar
- Google Drive
- connection status lookup
- connect URL generation
- generic provider calls
- custom integration calls
- app env fetch and caching

## Notes

- `auth_token` should be a valid Leash platform JWT
- `api_key` is optional, but useful for app-scoped access
- OAuth token handling remains a platform concern

## License

Apache-2.0
