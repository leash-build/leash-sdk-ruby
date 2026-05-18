# frozen_string_literal: true

require_relative "test_helper"

class TestTransport < Minitest::Test
  def test_call_constructs_correct_url
    client, runner = build_client
    client.integrations.gmail.list_labels
    assert_equal "/api/integrations/gmail/list-labels", runner.uri.path
    assert_equal "leash.test", runner.uri.host
  end

  def test_call_sends_x_api_key
    client, runner = build_client(api_key: "lsk_live_abc")
    client.integrations.gmail.list_labels
    assert_equal "lsk_live_abc", runner.request_headers["X-API-Key"]
  end

  def test_call_sends_cookie_when_present
    client, runner = build_client(request: rack_env(cookie: "jwt-xyz"))
    client.integrations.gmail.list_labels
    assert_equal "leash-auth=jwt-xyz", runner.request_headers["Cookie"]
  end

  def test_call_sends_content_type_json
    client, runner = build_client
    client.integrations.gmail.list_labels
    assert_equal "application/json", runner.request_headers["Content-Type"]
  end

  # Critical #1: bearer token must NEVER be forwarded on integration calls.
  def test_bearer_never_forwarded_on_integration_calls
    request = rack_env(cookie: "cookie-jwt", auth: "bearer-jwt")
    client, runner = build_client(request: request, api_key: "lsk_live_test")
    client.integrations.gmail.list_labels
    headers = runner.request_headers
    refute headers.key?("Authorization"),
      "Integration calls must not forward Authorization: Bearer header. Got: #{headers.inspect}"
    # And the platform-required headers DID make it through.
    assert_equal "lsk_live_test", headers["X-API-Key"]
    assert_equal "leash-auth=cookie-jwt", headers["Cookie"]
  end

  def test_bearer_never_forwarded_on_integration_calls_even_without_api_key
    request = rack_env(cookie: "cookie-jwt", auth: "bearer-jwt")
    # Build client without an API key — bearer is still suppressed on POSTs.
    transport = Leash::Transport.new(
      platform_url: "https://leash.test",
      api_key: nil,
      cookie_value: Leash::Auth.extract_cookie(request),
      http_runner: RecordingRunner.new(FakeResponse.new(200, '{"success":true,"data":{}}'))
    )
    client = Leash::Client.new(request: request, api_key: nil, transport: transport)
    runner = transport.instance_variable_get(:@http_runner)
    client.integrations.gmail.list_labels
    refute runner.request_headers.key?("Authorization")
  end

  def test_no_api_key_header_when_nil
    client, runner = build_client(api_key: nil)
    client.integrations.gmail.list_labels
    refute runner.request_headers.key?("X-API-Key")
  end

  def test_no_cookie_header_when_no_cookie
    client, runner = build_client(request: rack_env, api_key: "k")
    client.integrations.gmail.list_labels
    refute runner.request_headers.key?("Cookie")
  end

  # Error mapping
  def test_401_raises_unauthorized
    client, _ = build_client(canned: FakeResponse.new(401, '{"error":"bad creds"}'))
    err = assert_raises(Leash::UnauthorizedError) { client.integrations.gmail.list_labels }
    assert_equal "UNAUTHORIZED", err.code
    assert_equal 401, err.status
  end

  def test_402_raises_upgrade_required
    client, _ = build_client(canned: FakeResponse.new(402, '{"message":"upgrade to growth"}'))
    err = assert_raises(Leash::UpgradeRequiredError) { client.integrations.gmail.list_labels }
    assert_equal "UPGRADE_REQUIRED", err.code
    assert_includes err.message, "upgrade to growth"
  end

  def test_403_raises_connection_required
    client, _ = build_client(canned: FakeResponse.new(403, '{"error":"not connected"}'))
    err = assert_raises(Leash::ConnectionRequiredError) { client.integrations.gmail.list_labels }
    assert_equal "INTEGRATION_NOT_ENABLED", err.code
  end

  def test_500_raises_integration_error
    client, _ = build_client(canned: FakeResponse.new(500, '{"error":"broke"}'))
    err = assert_raises(Leash::Error) { client.integrations.gmail.list_labels }
    assert_equal "INTEGRATION_ERROR", err.code
    assert_equal "broke", err.message
  end

  def test_404_raises_integration_error
    client, _ = build_client(canned: FakeResponse.new(404, '{"error":"unknown action"}'))
    err = assert_raises(Leash::Error) { client.integrations.gmail.list_labels }
    assert_equal 404, err.status
  end

  def test_success_envelope_returns_data
    client, _ = build_client(canned: FakeResponse.new(200, '{"success":true,"data":{"items":[1,2,3]}}'))
    result = client.integrations.gmail.list_labels
    assert_equal({ "items" => [1, 2, 3] }, result)
  end

  def test_unwraps_data_when_no_success_field
    client, _ = build_client(canned: FakeResponse.new(200, '{"data":{"x":1}}'))
    result = client.integrations.gmail.list_labels
    assert_equal({ "x" => 1 }, result)
  end

  def test_returns_body_when_no_envelope
    client, _ = build_client(canned: FakeResponse.new(200, '[{"id":"1"}]'))
    result = client.integrations.gmail.list_labels
    assert_equal [{ "id" => "1" }], result
  end

  def test_success_false_raises_error
    client, _ = build_client(canned: FakeResponse.new(200, '{"success":false,"error":"oops","code":"not_connected","connectUrl":"https://x"}'))
    err = assert_raises(Leash::Error) { client.integrations.gmail.list_labels }
    assert_equal "not_connected", err.code
    assert_equal "https://x", err.connect_url
  end

  def test_platform_url_trailing_slash_stripped
    transport = Leash::Transport.new(platform_url: "https://x.test/", api_key: nil)
    assert_equal "https://x.test", transport.platform_url
  end

  def test_transport_network_error_on_runner_failure
    bad_runner = proc { raise SocketError, "no DNS" }
    transport = Leash::Transport.new(platform_url: "https://x", api_key: nil, http_runner: bad_runner)
    err = assert_raises(Leash::NetworkError) { transport.call("gmail", "list-labels") }
    assert_includes err.message, "no DNS"
  end
end
