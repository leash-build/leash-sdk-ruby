# frozen_string_literal: true

module Leash
  # Client for Google Calendar operations via the Leash platform proxy.
  #
  # Not instantiated directly -- use {Integrations#calendar} instead.
  class CalendarClient
    PROVIDER = "google_calendar"

    # @api private
    def initialize(call_fn)
      @call = call_fn
    end

    # List all calendars accessible to the user.
    #
    # @return [Hash] hash with calendar list data
    def list_calendars
      @call.call(PROVIDER, "list-calendars", {})
    end

    # List events on a calendar.
    #
    # @param calendar_id [String, nil] calendar identifier (defaults to "primary" on the server)
    # @param time_min [String, nil] lower bound for event start time (RFC 3339)
    # @param time_max [String, nil] upper bound for event start time (RFC 3339)
    # @param max_results [Integer, nil] maximum number of events to return
    # @param single_events [Boolean, nil] whether to expand recurring events
    # @param order_by [String, nil] sort order (e.g. "startTime", "updated")
    # @return [Hash] hash with "items" list of events
    def list_events(calendar_id: nil, time_min: nil, time_max: nil, max_results: nil, single_events: nil, order_by: nil)
      params = {}
      params["calendarId"] = calendar_id if calendar_id
      params["timeMin"] = time_min if time_min
      params["timeMax"] = time_max if time_max
      params["maxResults"] = max_results if max_results
      params["singleEvents"] = single_events unless single_events.nil?
      params["orderBy"] = order_by if order_by
      @call.call(PROVIDER, "list-events", params)
    end

    # Create a new calendar event.
    #
    # @param summary [String] event title
    # @param start [Hash, String] start time -- either an RFC 3339 string or a hash
    #   with keys "dateTime", "date", and/or "timeZone"
    # @param end_time [Hash, String] end time (same format as +start+)
    # @param calendar_id [String, nil] calendar identifier (defaults to "primary")
    # @param description [String, nil] event description
    # @param location [String, nil] event location
    # @param attendees [Array<Hash>, nil] list of attendee hashes (e.g. [{ "email" => "a@b.com" }])
    # @return [Hash] the created event object
    def create_event(summary:, start:, end_time:, calendar_id: nil, description: nil, location: nil, attendees: nil)
      params = { "summary" => summary, "start" => start, "end" => end_time }
      params["calendarId"] = calendar_id if calendar_id
      params["description"] = description if description
      params["location"] = location if location
      params["attendees"] = attendees if attendees
      @call.call(PROVIDER, "create-event", params)
    end

    # Get a single event by ID.
    #
    # @param event_id [String] the event identifier
    # @param calendar_id [String, nil] the calendar identifier
    # @return [Hash] the event object
    def get_event(event_id, calendar_id: nil)
      params = { "eventId" => event_id }
      params["calendarId"] = calendar_id if calendar_id
      @call.call(PROVIDER, "get-event", params)
    end
  end
end
