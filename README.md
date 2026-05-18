# Leash SDK for Ruby

Server-side Ruby SDK for the [Leash](https://leash.build) platform. One client gives you:

- the authenticated user off the request
- runtime env-var resolution from the Leash secret-source registry
- typed integrations (Gmail, Google Calendar, Google Drive, Linear)
- a generic escape hatch for any provider on the platform

Framework-agnostic: works with **Rails**, **Sinatra**, **Hanami**, or plain **Rack** — no framework gems required.

## Installation

Add to your `Gemfile`:

```ruby
gem "leash-sdk"
```

…or install directly:

```bash
gem install leash-sdk
```

Requires Ruby `>= 2.7`. The only runtime dependency is [`jwt`](https://rubygems.org/gems/jwt).

## Setup

Set the platform API key in your environment:

```bash
export LEASH_API_KEY=lsk_live_...
```

The constructor reads `LEASH_API_KEY` automatically; you can also pass `api_key:` explicitly.

## Usage

### Rails

```ruby
# app/controllers/inbox_controller.rb
class InboxController < ApplicationController
  def index
    leash = Leash.new(request: request)

    if leash.auth.authenticated?
      @user = leash.auth.user                           # Leash::User or nil
      @messages = leash.integrations.gmail.list_messages(max_results: 10)
    else
      redirect_to "/login"
    end
  end
end
```

### Sinatra

```ruby
require "sinatra"
require "leash"

get "/me" do
  leash = Leash.new(request: request)
  user = leash.auth.user
  halt 401 unless user
  user.to_h.to_json
end
```

### Plain Rack

```ruby
class MyApp
  def call(env)
    leash = Leash.new(request: env)        # Rack `env` hash works directly
    secret = leash.env.get("OPENAI_API_KEY")
    [200, {}, [secret ? "ok" : "missing"]]
  end
end
```

## What you get

### `leash.auth`

```ruby
user = leash.auth.user                     # Leash::User or nil — never raises
leash.auth.authenticated?                  # Boolean
```

### `leash.env`

```ruby
key = leash.env.get("OPENAI_API_KEY")      # String or nil (nil = not declared)
fresh = leash.env.get("STRIPE_KEY", fresh: true)
many = leash.env.get_many(["A", "B"])      # { "A" => "...", "B" => nil }
```

Per-instance TTL cache: 60 seconds. Pass `fresh: true` to bypass the cache for one read.

### `leash.integrations`

Typed providers:

```ruby
# Gmail
leash.integrations.gmail.list_messages(max_results: 5)
leash.integrations.gmail.get_message("msg-id")
leash.integrations.gmail.send_message(to: "a@b.com", subject: "Hi", body: "Hello")
leash.integrations.gmail.search_messages("from:x@y.com")
leash.integrations.gmail.list_labels
leash.integrations.gmail.get_profile

# Google Calendar (also addressable as leash.integrations.google_calendar)
leash.integrations.calendar.list_calendars
leash.integrations.calendar.list_events(time_min: "2026-01-01T00:00:00Z")
leash.integrations.calendar.create_event(
  summary: "Standup",
  start: { "dateTime" => "2026-05-15T10:00:00Z" },
  end_time: { "dateTime" => "2026-05-15T10:30:00Z" }
)
leash.integrations.calendar.get_event("evt-1")

# Google Drive (also addressable as leash.integrations.google_drive)
leash.integrations.drive.list_files(query: "name contains 'q'")
leash.integrations.drive.get_file("file-id")
leash.integrations.drive.download_file("file-id")
leash.integrations.drive.create_folder("Receipts", parent_id: "p-1")
leash.integrations.drive.upload_file(name: "x.txt", content: "data", mime_type: "text/plain")
leash.integrations.drive.delete_file("file-id")
leash.integrations.drive.search_files("invoice")

# Linear
leash.integrations.linear.list_issues(state_type: "started")
leash.integrations.linear.get_issue("LEA-123")
leash.integrations.linear.create_issue(team_id: "t-1", title: "Build it")
leash.integrations.linear.update_issue("LEA-123", priority: 1)
leash.integrations.linear.add_comment("LEA-123", "ship it")
leash.integrations.linear.list_teams
leash.integrations.linear.list_projects
```

Generic escape hatch for any platform-registered provider (Slack, GitHub, HubSpot, Jira, …):

```ruby
leash.integrations.provider("slack").call("post_message",
                                            body: { "channel" => "#general", "text" => "hi" })
```

## Errors

Every call raises a `Leash::Error` (or one of its subclasses) on failure:

| Class                            | Raised when                                |
|----------------------------------|--------------------------------------------|
| `Leash::UnauthorizedError`       | platform returned 401 (missing/invalid creds) |
| `Leash::ConnectionRequiredError` | 403 (provider not connected for this user) |
| `Leash::UpgradeRequiredError`    | 402 (feature gated behind a higher plan)   |
| `Leash::KeyNotDeclaredError`     | manually raised for env mis-declarations   |
| `Leash::NetworkError`            | transport-level failures (DNS, refused, timeout) |
| `Leash::Error`                   | base class — also raised for generic 4xx/5xx |

Every error carries `code`, `message`, `action`, `see_also`, `status`, and (where present) `connect_url`.

For convenience, the 0.3 aliases `Leash::NotConnectedError` and `Leash::PlanBlockError` are still available.

## Authentication precedence

The constructor inspects the request in this order:

1. **`LEASH_API_KEY` env var** (or explicit `api_key:` constructor arg) — server-only, never request-bound.
2. **`Authorization: Bearer <jwt>`** header on the request — used by `auth.user` and as an env-read fallback when no API key is present. **Never** forwarded on integration POSTs.
3. **`leash-auth` cookie** on the request — the standard browser → deployed-app session.

The Bearer-token → env fallback is intentional so CLI/agent flows can read env-vars with a user JWT when no app key is provisioned. The same JWT is **never** sent on integration POSTs because the platform's `verifyToken()` rejects it before the API-key check runs, producing a misleading 401.

## What's NOT in 0.4 yet

- `create_dev_auth_handler` / `attach_local_dev_handler` — there's no Rack-side equivalent shipped in 0.4. (The TS SDK has a `Leash.createDevAuthHandler` for Next.js routes.) If you need a Ruby local-dev cookie-exchange flow, open an issue.
- Legacy `LeashIntegrations` class — the 0.3 `Leash::Integrations.new(auth_token: ..., api_key: ...)` constructor and its `gmail` / `calendar` / `drive` accessors have been replaced by `Leash.new(request: ...)` + the namespaced `.integrations` accessor. The TS SDK dropped the equivalent class in 0.4 too.
- Browser-mode usage — server-only in 0.4.

If you're upgrading from 0.3.x, the `Leash::Auth.get_user(request)` helper and the `Leash::User` / `Leash::Error` / `Leash::NotConnectedError` / `Leash::TokenExpiredError` classes are kept for backwards compatibility.

## Testing

```bash
bundle install
bundle exec rake test
```

## License

Apache 2.0.
