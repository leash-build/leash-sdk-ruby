# frozen_string_literal: true

require "minitest/autorun"
require "net/http"
require "json"

require_relative "../lib/leash"

# --------------------------------------------------------------------------
# Helpers: stub Net::HTTP.start to avoid real network calls.
# --------------------------------------------------------------------------

# A fake HTTP response object.
FakeResponse = Struct.new(:code, :body)

# Captures the last request made via Net::HTTP.start and returns a canned response.
module NetHTTPStub
  class << self
    attr_accessor :last_request, :canned_body, :canned_code, :call_count
  end

  self.canned_code = "200"
  self.canned_body = '{"success":true,"data":{}}'
  self.call_count = 0

  def self.reset!
    self.last_request = nil
    self.canned_code = "200"
    self.canned_body = '{"success":true,"data":{}}'
    self.call_count = 0
  end
end

# Save reference to original start method
NET_HTTP_ORIGINAL_START = Net::HTTP.method(:start)

# Monkey-patch Net::HTTP.start once at load time.
class << Net::HTTP
  def start(host, port = nil, **opts, &block)
    if NetHTTPStub.instance_variable_get(:@active)
      NetHTTPStub.call_count += 1
      fake_http = Object.new
      fake_http.define_singleton_method(:request) do |req|
        NetHTTPStub.last_request = req
        FakeResponse.new(NetHTTPStub.canned_code, NetHTTPStub.canned_body)
      end
      block.call(fake_http)
    else
      NET_HTTP_ORIGINAL_START.call(host, port, **opts, &block)
    end
  end
end

# --------------------------------------------------------------------------
# Tests
# --------------------------------------------------------------------------

class TestLeashClient < Minitest::Test
  def setup
    NetHTTPStub.instance_variable_set(:@active, true)
    NetHTTPStub.reset!
  end

  def teardown
    NetHTTPStub.instance_variable_set(:@active, false)
  end

  # ---- 1. Client initialization -------------------------------------------

  def test_default_platform_url
    client = Leash::Integrations.new(auth_token: "tok")
    client.call("gmail", "list-messages")
    uri = NetHTTPStub.last_request.uri
    assert_equal "https://leash.build", "#{uri.scheme}://#{uri.host}"
  end

  def test_custom_platform_url
    client = Leash::Integrations.new(auth_token: "tok", platform_url: "https://custom.example.com")
    client.call("gmail", "list-messages")
    uri = NetHTTPStub.last_request.uri
    assert_equal "custom.example.com", uri.host
  end

  def test_trailing_slash_stripped_from_platform_url
    client = Leash::Integrations.new(auth_token: "tok", platform_url: "https://custom.example.com/")
    client.call("gmail", "list-messages")
    uri = NetHTTPStub.last_request.uri
    assert_match %r{^/api/}, uri.path
  end

  def test_api_key_from_constructor
    client = Leash::Integrations.new(auth_token: "tok", api_key: "my-key")
    client.call("gmail", "list-messages")
    assert_equal "my-key", NetHTTPStub.last_request["X-API-Key"]
  end

  def test_api_key_from_env
    original = ENV["LEASH_API_KEY"]
    ENV["LEASH_API_KEY"] = "env-key"
    client = Leash::Integrations.new(auth_token: "tok")
    client.call("gmail", "list-messages")
    assert_equal "env-key", NetHTTPStub.last_request["X-API-Key"]
  ensure
    if original
      ENV["LEASH_API_KEY"] = original
    else
      ENV.delete("LEASH_API_KEY")
    end
  end

  def test_no_api_key_header_when_nil
    original = ENV.delete("LEASH_API_KEY")
    client = Leash::Integrations.new(auth_token: "tok")
    client.call("gmail", "list-messages")
    assert_nil NetHTTPStub.last_request["X-API-Key"]
  ensure
    ENV["LEASH_API_KEY"] = original if original
  end

  # ---- 2. Auth headers ----------------------------------------------------

  def test_authorization_header_bearer_token
    client = Leash::Integrations.new(auth_token: "my-jwt")
    client.call("gmail", "list-messages")
    assert_equal "Bearer my-jwt", NetHTTPStub.last_request["Authorization"]
  end

  def test_content_type_json
    client = Leash::Integrations.new(auth_token: "tok")
    client.call("gmail", "list-messages")
    assert_equal "application/json", NetHTTPStub.last_request["Content-Type"]
  end

  # ---- 3. URL construction ------------------------------------------------

  def test_call_url_construction
    client = Leash::Integrations.new(auth_token: "tok")
    client.call("gmail", "list-messages")
    assert_equal "/api/integrations/gmail/list-messages", NetHTTPStub.last_request.uri.path
  end

  def test_connections_url
    NetHTTPStub.canned_body = '{"success":true,"data":[]}'
    client = Leash::Integrations.new(auth_token: "tok")
    client.connections
    assert_equal "/api/integrations/connections", NetHTTPStub.last_request.uri.path
  end

  def test_connect_url_without_return
    client = Leash::Integrations.new(auth_token: "tok", platform_url: "https://leash.build")
    url = client.connect_url("gmail")
    assert_equal "https://leash.build/api/integrations/connect/gmail", url
  end

  def test_connect_url_with_return
    client = Leash::Integrations.new(auth_token: "tok", platform_url: "https://leash.build")
    url = client.connect_url("gmail", return_url: "https://myapp.com/callback")
    assert_includes url, "return_url=https%3A%2F%2Fmyapp.com%2Fcallback"
  end

  def test_env_url
    NetHTTPStub.canned_body = '{"success":true,"data":{"FOO":"bar"}}'
    client = Leash::Integrations.new(auth_token: "tok")
    client.get_env
    assert_equal "/api/apps/env", NetHTTPStub.last_request.uri.path
  end

  def test_mcp_url
    client = Leash::Integrations.new(auth_token: "tok")
    client.mcp("@modelcontextprotocol/server-github", "list_issues")
    assert_equal "/api/mcp/run", NetHTTPStub.last_request.uri.path
  end

  def test_custom_integration_url
    client = Leash::Integrations.new(auth_token: "tok")
    stripe = client.integration("stripe")
    stripe.call("/v1/charges", method: "GET")
    assert_equal "/api/integrations/custom/stripe", NetHTTPStub.last_request.uri.path
  end

  # ---- 4. Provider clients -------------------------------------------------

  def test_gmail_client_returned
    client = Leash::Integrations.new(auth_token: "tok")
    assert_instance_of Leash::GmailClient, client.gmail
  end

  def test_calendar_client_returned
    client = Leash::Integrations.new(auth_token: "tok")
    assert_instance_of Leash::CalendarClient, client.calendar
  end

  def test_drive_client_returned
    client = Leash::Integrations.new(auth_token: "tok")
    assert_instance_of Leash::DriveClient, client.drive
  end

  def test_gmail_cached
    client = Leash::Integrations.new(auth_token: "tok")
    assert_same client.gmail, client.gmail
  end

  def test_calendar_cached
    client = Leash::Integrations.new(auth_token: "tok")
    assert_same client.calendar, client.calendar
  end

  def test_drive_cached
    client = Leash::Integrations.new(auth_token: "tok")
    assert_same client.drive, client.drive
  end

  def test_gmail_list_messages_provider_and_action
    client = Leash::Integrations.new(auth_token: "tok")
    client.gmail.list_messages(query: "is:unread")
    assert_equal "/api/integrations/gmail/list-messages", NetHTTPStub.last_request.uri.path
    body = JSON.parse(NetHTTPStub.last_request.body)
    assert_equal "is:unread", body["query"]
    assert_equal 20, body["maxResults"]
  end

  def test_gmail_get_message
    client = Leash::Integrations.new(auth_token: "tok")
    client.gmail.get_message("msg-123")
    body = JSON.parse(NetHTTPStub.last_request.body)
    assert_equal "msg-123", body["messageId"]
    assert_equal "full", body["format"]
  end

  def test_gmail_send_message
    client = Leash::Integrations.new(auth_token: "tok")
    client.gmail.send_message(to: "a@b.com", subject: "Hi", body: "Hello")
    body = JSON.parse(NetHTTPStub.last_request.body)
    assert_equal "a@b.com", body["to"]
    assert_equal "Hi", body["subject"]
  end

  def test_gmail_search_messages
    client = Leash::Integrations.new(auth_token: "tok")
    client.gmail.search_messages("from:x@y.com")
    assert_equal "/api/integrations/gmail/search-messages", NetHTTPStub.last_request.uri.path
  end

  def test_gmail_list_labels
    client = Leash::Integrations.new(auth_token: "tok")
    client.gmail.list_labels
    assert_equal "/api/integrations/gmail/list-labels", NetHTTPStub.last_request.uri.path
  end

  def test_calendar_list_events
    client = Leash::Integrations.new(auth_token: "tok")
    client.calendar.list_events(time_min: "2026-01-01T00:00:00Z")
    assert_equal "/api/integrations/google_calendar/list-events", NetHTTPStub.last_request.uri.path
    body = JSON.parse(NetHTTPStub.last_request.body)
    assert_equal "2026-01-01T00:00:00Z", body["timeMin"]
  end

  def test_calendar_create_event
    client = Leash::Integrations.new(auth_token: "tok")
    client.calendar.create_event(
      summary: "Meeting",
      start: "2026-04-10T10:00:00Z",
      end_time: "2026-04-10T11:00:00Z"
    )
    assert_equal "/api/integrations/google_calendar/create-event", NetHTTPStub.last_request.uri.path
    body = JSON.parse(NetHTTPStub.last_request.body)
    assert_equal "Meeting", body["summary"]
  end

  def test_calendar_get_event
    client = Leash::Integrations.new(auth_token: "tok")
    client.calendar.get_event("evt-1")
    body = JSON.parse(NetHTTPStub.last_request.body)
    assert_equal "evt-1", body["eventId"]
  end

  def test_calendar_list_calendars
    client = Leash::Integrations.new(auth_token: "tok")
    client.calendar.list_calendars
    assert_equal "/api/integrations/google_calendar/list-calendars", NetHTTPStub.last_request.uri.path
  end

  def test_drive_list_files
    client = Leash::Integrations.new(auth_token: "tok")
    client.drive.list_files(query: "name contains 'report'")
    assert_equal "/api/integrations/google_drive/list-files", NetHTTPStub.last_request.uri.path
    body = JSON.parse(NetHTTPStub.last_request.body)
    assert_equal "name contains 'report'", body["query"]
  end

  def test_drive_get_file
    client = Leash::Integrations.new(auth_token: "tok")
    client.drive.get_file("file-42")
    body = JSON.parse(NetHTTPStub.last_request.body)
    assert_equal "file-42", body["fileId"]
  end

  def test_drive_search_files
    client = Leash::Integrations.new(auth_token: "tok")
    client.drive.search_files("budget")
    assert_equal "/api/integrations/google_drive/search-files", NetHTTPStub.last_request.uri.path
  end

  # ---- 5. Error handling ---------------------------------------------------

  def test_not_connected_error
    NetHTTPStub.canned_body = '{"success":false,"error":"Gmail not connected","code":"not_connected","connectUrl":"https://leash.build/connect/gmail"}'
    client = Leash::Integrations.new(auth_token: "tok")
    err = assert_raises(Leash::NotConnectedError) { client.call("gmail", "list-messages") }
    assert_equal "not_connected", err.code
    assert_equal "https://leash.build/connect/gmail", err.connect_url
    assert_equal "Gmail not connected", err.message
  end

  def test_token_expired_error
    NetHTTPStub.canned_body = '{"success":false,"error":"Token expired","code":"token_expired","connectUrl":"https://leash.build/connect/gmail"}'
    client = Leash::Integrations.new(auth_token: "tok")
    err = assert_raises(Leash::TokenExpiredError) { client.call("gmail", "list-messages") }
    assert_equal "token_expired", err.code
    assert_includes err.message, "Token expired"
  end

  def test_generic_error
    NetHTTPStub.canned_body = '{"success":false,"error":"Something broke","code":"internal_error"}'
    client = Leash::Integrations.new(auth_token: "tok")
    err = assert_raises(Leash::Error) { client.call("gmail", "list-messages") }
    assert_equal "internal_error", err.code
    assert_equal "Something broke", err.message
  end

  def test_error_without_code
    NetHTTPStub.canned_body = '{"success":false,"error":"Unknown error"}'
    client = Leash::Integrations.new(auth_token: "tok")
    err = assert_raises(Leash::Error) { client.call("gmail", "list-messages") }
    assert_nil err.code
  end

  def test_error_hierarchy
    assert Leash::NotConnectedError < Leash::Error
    assert Leash::TokenExpiredError < Leash::Error
    assert Leash::Error < StandardError
  end

  # ---- 6. Env caching ------------------------------------------------------

  def test_get_env_returns_all
    NetHTTPStub.canned_body = '{"success":true,"data":{"DB_URL":"postgres://localhost","SECRET":"shhh"}}'
    client = Leash::Integrations.new(auth_token: "tok")
    env = client.get_env
    assert_equal "postgres://localhost", env["DB_URL"]
    assert_equal "shhh", env["SECRET"]
  end

  def test_get_env_returns_single_key
    NetHTTPStub.canned_body = '{"success":true,"data":{"DB_URL":"postgres://localhost"}}'
    client = Leash::Integrations.new(auth_token: "tok")
    assert_equal "postgres://localhost", client.get_env("DB_URL")
  end

  def test_get_env_returns_nil_for_missing_key
    NetHTTPStub.canned_body = '{"success":true,"data":{"DB_URL":"pg"}}'
    client = Leash::Integrations.new(auth_token: "tok")
    assert_nil client.get_env("NOPE")
  end

  def test_env_is_cached
    NetHTTPStub.canned_body = '{"success":true,"data":{"A":"1"}}'
    client = Leash::Integrations.new(auth_token: "tok")
    client.get_env
    client.get_env
    client.get_env("A")
    assert_equal 1, NetHTTPStub.call_count, "get_env should only make one HTTP call (caching)"
  end

  # ---- 7. Connection status ------------------------------------------------

  def test_connected_true
    NetHTTPStub.canned_body = '{"success":true,"data":[{"providerId":"gmail","status":"active"}]}'
    client = Leash::Integrations.new(auth_token: "tok")
    assert client.connected?("gmail")
  end

  def test_connected_false_when_inactive
    NetHTTPStub.canned_body = '{"success":true,"data":[{"providerId":"gmail","status":"inactive"}]}'
    client = Leash::Integrations.new(auth_token: "tok")
    refute client.connected?("gmail")
  end

  def test_connected_false_when_missing
    NetHTTPStub.canned_body = '{"success":true,"data":[]}'
    client = Leash::Integrations.new(auth_token: "tok")
    refute client.connected?("gmail")
  end

  def test_connected_false_on_error
    NetHTTPStub.canned_body = '{"success":false,"error":"boom"}'
    client = Leash::Integrations.new(auth_token: "tok")
    refute client.connected?("gmail")
  end

  # ---- 8. No web framework dependencies ------------------------------------

  def test_no_rails_dependency
    loaded = $LOADED_FEATURES.select { |f| f.include?("leash") }
    loaded.each do |path|
      refute path.include?("rails"), "Leash should not load Rails"
      refute path.include?("sinatra"), "Leash should not load Sinatra"
      refute path.include?("rack"), "Leash should not load Rack"
    end
  end

  def test_only_stdlib_dependencies
    assert defined?(Net::HTTP), "Net::HTTP should be available"
    assert defined?(JSON), "JSON should be available"
    assert defined?(URI), "URI should be available"
  end

  # ---- MCP call body -------------------------------------------------------

  def test_mcp_sends_correct_payload
    client = Leash::Integrations.new(auth_token: "tok")
    client.mcp("@modelcontextprotocol/server-github", "list_issues", { "repo" => "leash" })
    body = JSON.parse(NetHTTPStub.last_request.body)
    assert_equal "@modelcontextprotocol/server-github", body["package"]
    assert_equal "list_issues", body["tool"]
    assert_equal({ "repo" => "leash" }, body["args"])
  end

  def test_mcp_omits_args_when_empty
    client = Leash::Integrations.new(auth_token: "tok")
    client.mcp("pkg", "tool")
    body = JSON.parse(NetHTTPStub.last_request.body)
    refute body.key?("args"), "args should be omitted when empty"
  end

  # ---- Custom integration body ---------------------------------------------

  def test_custom_integration_forwards_body_and_headers
    client = Leash::Integrations.new(auth_token: "tok")
    stripe = client.integration("stripe")
    stripe.call("/v1/charges", method: "POST", body: { "amount" => 100 }, headers: { "Idempotency-Key" => "abc" })
    payload = JSON.parse(NetHTTPStub.last_request.body)
    assert_equal "/v1/charges", payload["path"]
    assert_equal "POST", payload["method"]
    assert_equal({ "amount" => 100 }, payload["body"])
    assert_equal({ "Idempotency-Key" => "abc" }, payload["headers"])
  end

  # ---- Return value --------------------------------------------------------

  def test_call_returns_data_field
    NetHTTPStub.canned_body = '{"success":true,"data":{"messages":[{"id":"1"}]}}'
    client = Leash::Integrations.new(auth_token: "tok")
    result = client.call("gmail", "list-messages")
    assert_equal({ "messages" => [{ "id" => "1" }] }, result)
  end

  # ---- get_access_token ----------------------------------------------------

  def test_get_access_token_url_and_method
    NetHTTPStub.canned_body = '{"success":true,"data":{"accessToken":"slack-xoxb-abc","provider":"slack"}}'
    client = Leash::Integrations.new(auth_token: "tok")
    client.get_access_token("slack")
    assert_equal "/api/integrations/token", NetHTTPStub.last_request.uri.path
    assert_instance_of Net::HTTP::Post, NetHTTPStub.last_request
  end

  def test_get_access_token_sends_provider_in_body
    NetHTTPStub.canned_body = '{"success":true,"data":{"accessToken":"slack-xoxb-abc","provider":"slack"}}'
    client = Leash::Integrations.new(auth_token: "tok")
    client.get_access_token("slack")
    body = JSON.parse(NetHTTPStub.last_request.body)
    assert_equal "slack", body["provider"]
  end

  def test_get_access_token_sends_auth_headers
    NetHTTPStub.canned_body = '{"success":true,"data":{"accessToken":"tkn","provider":"gmail"}}'
    client = Leash::Integrations.new(auth_token: "my-jwt", api_key: "my-key")
    client.get_access_token("gmail")
    assert_equal "Bearer my-jwt", NetHTTPStub.last_request["Authorization"]
    assert_equal "my-key", NetHTTPStub.last_request["X-API-Key"]
    assert_equal "application/json", NetHTTPStub.last_request["Content-Type"]
  end

  def test_get_access_token_returns_token_string
    NetHTTPStub.canned_body = '{"success":true,"data":{"accessToken":"slack-xoxb-abc","provider":"slack"}}'
    client = Leash::Integrations.new(auth_token: "tok")
    assert_equal "slack-xoxb-abc", client.get_access_token("slack")
  end

  def test_get_access_token_not_connected_error
    NetHTTPStub.canned_body = '{"success":false,"error":"Slack not connected","code":"not_connected","connectUrl":"https://leash.build/connect/slack"}'
    client = Leash::Integrations.new(auth_token: "tok")
    err = assert_raises(Leash::NotConnectedError) { client.get_access_token("slack") }
    assert_equal "not_connected", err.code
    assert_equal "https://leash.build/connect/slack", err.connect_url
    assert_equal "Slack not connected", err.message
  end

  def test_get_access_token_token_expired_error
    NetHTTPStub.canned_body = '{"success":false,"error":"Token expired","code":"token_expired","connectUrl":"https://leash.build/connect/gmail"}'
    client = Leash::Integrations.new(auth_token: "tok")
    err = assert_raises(Leash::TokenExpiredError) { client.get_access_token("gmail") }
    assert_equal "token_expired", err.code
  end

  # ---- get_custom_mcp_config -----------------------------------------------

  def test_get_custom_mcp_config_url_and_method
    NetHTTPStub.canned_body = '{"success":true,"data":{"slug":"acme","displayName":"Acme MCP","url":"https://mcp.acme.com","headers":{}}}'
    client = Leash::Integrations.new(auth_token: "tok")
    client.get_custom_mcp_config("acme")
    assert_equal "/api/integrations/mcp-config/acme", NetHTTPStub.last_request.uri.path
    assert_instance_of Net::HTTP::Get, NetHTTPStub.last_request
  end

  def test_get_custom_mcp_config_url_encodes_slug
    NetHTTPStub.canned_body = '{"success":true,"data":{"slug":"acme/v2","displayName":"Acme","url":"https://mcp.acme.com","headers":{}}}'
    client = Leash::Integrations.new(auth_token: "tok")
    client.get_custom_mcp_config("acme/v2")
    assert_equal "/api/integrations/mcp-config/acme%2Fv2", NetHTTPStub.last_request.uri.path
  end

  def test_get_custom_mcp_config_sends_auth_headers
    NetHTTPStub.canned_body = '{"success":true,"data":{"slug":"acme","displayName":"Acme MCP","url":"https://mcp.acme.com","headers":{}}}'
    client = Leash::Integrations.new(auth_token: "my-jwt", api_key: "my-key")
    client.get_custom_mcp_config("acme")
    assert_equal "Bearer my-jwt", NetHTTPStub.last_request["Authorization"]
    assert_equal "my-key", NetHTTPStub.last_request["X-API-Key"]
  end

  def test_get_custom_mcp_config_returns_full_config
    NetHTTPStub.canned_body = '{"success":true,"data":{"slug":"acme","displayName":"Acme MCP","url":"https://mcp.acme.com","headers":{"Authorization":"Bearer xyz"}}}'
    client = Leash::Integrations.new(auth_token: "tok")
    config = client.get_custom_mcp_config("acme")
    assert_equal "acme", config["slug"]
    assert_equal "Acme MCP", config["displayName"]
    assert_equal "https://mcp.acme.com", config["url"]
    assert_equal({ "Authorization" => "Bearer xyz" }, config["headers"])
  end

  def test_get_custom_mcp_config_unknown_mcp_server_error
    NetHTTPStub.canned_body = '{"success":false,"error":"Unknown MCP server","code":"unknown_mcp_server"}'
    client = Leash::Integrations.new(auth_token: "tok")
    err = assert_raises(Leash::Error) { client.get_custom_mcp_config("nope") }
    assert_equal "unknown_mcp_server", err.code
    assert_equal "Unknown MCP server", err.message
  end

  def test_get_custom_mcp_config_invalid_api_key_error
    NetHTTPStub.canned_body = '{"success":false,"error":"Invalid API key","code":"invalid_api_key"}'
    client = Leash::Integrations.new(auth_token: "tok")
    err = assert_raises(Leash::Error) { client.get_custom_mcp_config("acme") }
    assert_equal "invalid_api_key", err.code
  end
end
