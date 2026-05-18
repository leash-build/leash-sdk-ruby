# frozen_string_literal: true

require_relative "test_helper"

class TestIntegrationsGmail < Minitest::Test
  def setup
    @client, @runner = build_client
  end

  def test_list_messages_url_and_body
    @client.integrations.gmail.list_messages(max_results: 10, query: "is:unread")
    assert_equal "/api/integrations/gmail/list-messages", @runner.uri.path
    assert_equal({ "query" => "is:unread", "maxResults" => 10 }, @runner.request_body)
  end

  def test_list_messages_with_no_args_sends_empty_body
    @client.integrations.gmail.list_messages
    assert_equal "/api/integrations/gmail/list-messages", @runner.uri.path
    assert_equal({}, @runner.request_body || {})
  end

  def test_list_messages_full_params
    @client.integrations.gmail.list_messages(
      query: "x", max_results: 3, label_ids: ["INBOX"], page_token: "next"
    )
    assert_equal({
      "query" => "x", "maxResults" => 3, "labelIds" => ["INBOX"], "pageToken" => "next"
    }, @runner.request_body)
  end

  def test_get_message
    @client.integrations.gmail.get_message("msg-1")
    assert_equal "/api/integrations/gmail/get-message", @runner.uri.path
    assert_equal({ "messageId" => "msg-1", "format" => "full" }, @runner.request_body)
  end

  def test_get_message_with_format
    @client.integrations.gmail.get_message("msg-1", format: "metadata")
    assert_equal({ "messageId" => "msg-1", "format" => "metadata" }, @runner.request_body)
  end

  def test_send_message
    @client.integrations.gmail.send_message(
      to: "a@b.com", subject: "Hi", body: "Hello"
    )
    assert_equal "/api/integrations/gmail/send-message", @runner.uri.path
    body = @runner.request_body
    assert_equal "a@b.com", body["to"]
    assert_equal "Hi", body["subject"]
    assert_equal "Hello", body["body"]
  end

  def test_send_message_with_cc_bcc
    @client.integrations.gmail.send_message(
      to: "a@b.com", subject: "S", body: "B", cc: "c@d.com", bcc: "e@f.com"
    )
    body = @runner.request_body
    assert_equal "c@d.com", body["cc"]
    assert_equal "e@f.com", body["bcc"]
  end

  def test_search_messages
    @client.integrations.gmail.search_messages("from:x@y.com", max_results: 5)
    assert_equal "/api/integrations/gmail/search-messages", @runner.uri.path
    assert_equal({ "query" => "from:x@y.com", "maxResults" => 5 }, @runner.request_body)
  end

  def test_list_labels
    @client.integrations.gmail.list_labels
    assert_equal "/api/integrations/gmail/list-labels", @runner.uri.path
  end

  def test_get_profile
    @client.integrations.gmail.get_profile
    assert_equal "/api/integrations/gmail/get-profile", @runner.uri.path
  end

  # Verb count check
  def test_six_verbs_exposed
    verbs = %i[list_messages get_message send_message search_messages list_labels get_profile]
    verbs.each { |v| assert @client.integrations.gmail.respond_to?(v), "missing verb #{v}" }
    assert_equal 6, verbs.length
  end

  # 401 propagation through gmail
  def test_gmail_propagates_401
    client, _ = build_client(canned: FakeResponse.new(401, '{"error":"no auth"}'))
    assert_raises(Leash::UnauthorizedError) { client.integrations.gmail.list_labels }
  end

  # 402 propagation
  def test_gmail_propagates_402
    client, _ = build_client(canned: FakeResponse.new(402, '{"message":"upgrade"}'))
    assert_raises(Leash::UpgradeRequiredError) { client.integrations.gmail.list_labels }
  end

  # 403 propagation
  def test_gmail_propagates_403
    client, _ = build_client(canned: FakeResponse.new(403, '{"error":"not connected"}'))
    assert_raises(Leash::ConnectionRequiredError) { client.integrations.gmail.list_labels }
  end

  # 404 propagation
  def test_gmail_propagates_404
    client, _ = build_client(canned: FakeResponse.new(404, '{"error":"nope"}'))
    assert_raises(Leash::Error) { client.integrations.gmail.list_labels }
  end

  # 500 propagation
  def test_gmail_propagates_500
    client, _ = build_client(canned: FakeResponse.new(500, '{"error":"server broke"}'))
    err = assert_raises(Leash::Error) { client.integrations.gmail.list_labels }
    assert_equal "server broke", err.message
  end
end
