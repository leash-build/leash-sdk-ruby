# Leash SDK for Ruby

Ruby SDK for the [Leash](https://leash.build) platform integrations API. Access Gmail, Google Calendar, Google Drive, and more through the Leash platform proxy.

## Installation

Add to your Gemfile:

```ruby
gem "leash-sdk"
```

Or install directly:

```
gem install leash-sdk
```

## Quick Start

```ruby
require "leash"

client = Leash::Integrations.new(auth_token: ENV["LEASH_AUTH_TOKEN"])

# Gmail
messages = client.gmail.list_messages(query: "is:unread", max_results: 10)
message  = client.gmail.get_message("msg_id_123")
client.gmail.send_message(to: "friend@example.com", subject: "Hello", body: "Hi there!")
labels = client.gmail.list_labels

# Google Calendar
calendars = client.calendar.list_calendars
events    = client.calendar.list_events(
  time_min: "2026-04-10T00:00:00Z",
  time_max: "2026-04-17T00:00:00Z",
  single_events: true,
  order_by: "startTime"
)
client.calendar.create_event(
  summary: "Team standup",
  start: { "dateTime" => "2026-04-11T09:00:00-04:00" },
  end_time: { "dateTime" => "2026-04-11T09:30:00-04:00" }
)

# Google Drive
files = client.drive.list_files
file  = client.drive.get_file("file_id_123")
results = client.drive.search_files("quarterly report", max_results: 5)
```

## Connection Management

```ruby
# Check if a provider is connected
client.connected?("gmail")  # => true/false

# Get all connections
client.connections  # => [{ "providerId" => "gmail", "status" => "active", ... }]

# Get OAuth connect URL (for UI buttons)
url = client.connect_url("gmail", return_url: "https://myapp.com/settings")
```

## Error Handling

```ruby
begin
  client.gmail.list_messages
rescue Leash::NotConnectedError => e
  # Redirect user to connect: e.connect_url
  puts "Please connect Gmail: #{e.connect_url}"
rescue Leash::TokenExpiredError => e
  # Token needs refresh: e.connect_url
  puts "Token expired, reconnect: #{e.connect_url}"
rescue Leash::Error => e
  # General API error
  puts "Error (#{e.code}): #{e.message}"
end
```

## Configuration

```ruby
# Custom platform URL
client = Leash::Integrations.new(
  auth_token: "your-token",
  platform_url: "https://your-instance.leash.build"
)
```

## API Reference

### `Leash::Integrations.new(auth_token:, platform_url: "https://leash.build")`

Creates a new client instance.

### Gmail (`client.gmail`)

| Method | Description |
|--------|-------------|
| `list_messages(query:, max_results:, label_ids:, page_token:)` | List messages |
| `get_message(message_id, format:)` | Get a message by ID |
| `send_message(to:, subject:, body:, cc:, bcc:)` | Send an email |
| `search_messages(query, max_results:)` | Search messages |
| `list_labels` | List all labels |

### Calendar (`client.calendar`)

| Method | Description |
|--------|-------------|
| `list_calendars` | List all calendars |
| `list_events(calendar_id:, time_min:, time_max:, max_results:, single_events:, order_by:)` | List events |
| `create_event(summary:, start:, end_time:, calendar_id:, description:, location:, attendees:)` | Create an event |
| `get_event(event_id, calendar_id:)` | Get an event by ID |

### Drive (`client.drive`)

| Method | Description |
|--------|-------------|
| `list_files(query:, max_results:, folder_id:)` | List files |
| `get_file(file_id)` | Get file metadata |
| `search_files(query, max_results:)` | Search files |

### Connections

| Method | Description |
|--------|-------------|
| `connected?(provider_id)` | Check if provider is connected |
| `connections` | Get all connection statuses |
| `connect_url(provider_id, return_url:)` | Get OAuth connect URL |

## Requirements

- Ruby >= 3.0
- No external dependencies (uses stdlib `net/http`, `json`, `uri`)

## License

MIT
