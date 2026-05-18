# frozen_string_literal: true

require_relative "test_helper"

class TestProviderEscapeHatch < Minitest::Test
  def setup
    @client, @runner = build_client
  end

  def test_provider_returns_caller
    caller = @client.integrations.provider("slack")
    assert_instance_of Leash::Integrations::Caller, caller
    assert_equal "slack", caller.name
  end

  def test_caller_call_constructs_url
    @client.integrations.provider("slack").call("post_message", body: { "channel" => "#general", "text" => "hi" })
    assert_equal "/api/integrations/slack/post_message", @runner.uri.path
    assert_equal({ "channel" => "#general", "text" => "hi" }, @runner.request_body)
  end

  def test_caller_call_without_body
    @client.integrations.provider("github").call("list_repos")
    assert_equal "/api/integrations/github/list_repos", @runner.uri.path
    assert_equal({}, @runner.request_body || {})
  end

  def test_caller_propagates_errors
    client, _ = build_client(canned: FakeResponse.new(403, '{"error":"not connected"}'))
    assert_raises(Leash::ConnectionRequiredError) do
      client.integrations.provider("slack").call("post_message")
    end
  end

  def test_caller_unwraps_data_envelope
    client, _ = build_client(canned: FakeResponse.new(200, '{"success":true,"data":{"ok":true}}'))
    result = client.integrations.provider("slack").call("post_message", body: { "x" => 1 })
    assert_equal({ "ok" => true }, result)
  end
end
