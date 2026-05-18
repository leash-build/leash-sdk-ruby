# frozen_string_literal: true

require_relative "test_helper"

class TestIntegrationsCalendar < Minitest::Test
  def setup
    @client, @runner = build_client
  end

  def test_list_calendars_url
    @client.integrations.calendar.list_calendars
    assert_equal "/api/integrations/google_calendar/list-calendars", @runner.uri.path
  end

  def test_list_events_no_args
    @client.integrations.calendar.list_events
    assert_equal "/api/integrations/google_calendar/list-events", @runner.uri.path
    assert_equal({}, @runner.request_body || {})
  end

  def test_list_events_with_args
    @client.integrations.calendar.list_events(
      calendar_id: "primary",
      time_min: "2026-01-01T00:00:00Z",
      time_max: "2026-12-31T23:59:59Z",
      max_results: 25,
      query: "standup",
      single_events: true,
      order_by: "startTime"
    )
    body = @runner.request_body
    assert_equal "primary", body["calendarId"]
    assert_equal "2026-01-01T00:00:00Z", body["timeMin"]
    assert_equal "2026-12-31T23:59:59Z", body["timeMax"]
    assert_equal 25, body["maxResults"]
    assert_equal "standup", body["query"]
    assert_equal true, body["singleEvents"]
    assert_equal "startTime", body["orderBy"]
  end

  def test_create_event_minimal
    @client.integrations.calendar.create_event(
      summary: "Meeting",
      start: { "dateTime" => "2026-05-15T10:00:00Z" },
      end_time: { "dateTime" => "2026-05-15T11:00:00Z" }
    )
    assert_equal "/api/integrations/google_calendar/create-event", @runner.uri.path
    body = @runner.request_body
    assert_equal "Meeting", body["summary"]
    assert_equal "2026-05-15T10:00:00Z", body["start"]["dateTime"]
    assert_equal "2026-05-15T11:00:00Z", body["end"]["dateTime"]
  end

  def test_create_event_full
    @client.integrations.calendar.create_event(
      summary: "Standup",
      start: { "dateTime" => "2026-05-15T10:00:00Z" },
      end_time: { "dateTime" => "2026-05-15T10:30:00Z" },
      calendar_id: "team@example.com",
      description: "daily",
      location: "Zoom",
      attendees: [{ "email" => "a@b.com" }]
    )
    body = @runner.request_body
    assert_equal "team@example.com", body["calendarId"]
    assert_equal "daily", body["description"]
    assert_equal "Zoom", body["location"]
    assert_equal [{ "email" => "a@b.com" }], body["attendees"]
  end

  def test_get_event
    @client.integrations.calendar.get_event("evt-1")
    assert_equal "/api/integrations/google_calendar/get-event", @runner.uri.path
    assert_equal({ "eventId" => "evt-1" }, @runner.request_body)
  end

  def test_get_event_with_calendar_id
    @client.integrations.calendar.get_event("evt-1", calendar_id: "primary")
    assert_equal({ "eventId" => "evt-1", "calendarId" => "primary" }, @runner.request_body)
  end

  def test_four_verbs_exposed
    verbs = %i[list_calendars list_events create_event get_event]
    verbs.each { |v| assert @client.integrations.calendar.respond_to?(v), "missing verb #{v}" }
    assert_equal 4, verbs.length
  end

  def test_calendar_propagates_401
    client, _ = build_client(canned: FakeResponse.new(401, '{"error":"no"}'))
    assert_raises(Leash::UnauthorizedError) { client.integrations.calendar.list_calendars }
  end

  def test_calendar_propagates_402
    client, _ = build_client(canned: FakeResponse.new(402, '{"message":"upgrade"}'))
    assert_raises(Leash::UpgradeRequiredError) { client.integrations.calendar.list_calendars }
  end

  def test_calendar_propagates_404
    client, _ = build_client(canned: FakeResponse.new(404, '{"error":"nope"}'))
    assert_raises(Leash::Error) { client.integrations.calendar.list_calendars }
  end

  def test_calendar_propagates_500
    client, _ = build_client(canned: FakeResponse.new(500, '{"error":"server broke"}'))
    assert_raises(Leash::Error) { client.integrations.calendar.list_calendars }
  end
end
