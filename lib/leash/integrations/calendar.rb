# frozen_string_literal: true

require_relative "base"

module Leash
  module Integrations
    # `leash.integrations.calendar` — mirrors TS `leash.integrations.calendar`.
    # Wire provider id is `google_calendar` (also aliased as
    # `leash.integrations.google_calendar`).
    class Calendar < Base
      PROVIDER = "google_calendar"

      def list_calendars
        call("list-calendars")
      end

      # @param calendar_id [String, nil]
      # @param time_min [String, nil] ISO 8601 timestamp
      # @param time_max [String, nil] ISO 8601 timestamp
      # @param max_results [Integer, nil]
      # @param query [String, nil]
      # @param single_events [Boolean, nil]
      # @param order_by [String, nil]
      def list_events(calendar_id: nil, time_min: nil, time_max: nil,
                      max_results: nil, query: nil, single_events: nil,
                      order_by: nil)
        params = compact_params(
          "calendarId" => calendar_id,
          "timeMin" => time_min,
          "timeMax" => time_max,
          "maxResults" => max_results,
          "query" => query,
          "singleEvents" => single_events,
          "orderBy" => order_by
        )
        call("list-events", params.empty? ? nil : params)
      end

      # `end_time:` keyword is used here (not `end:`) to avoid clashing with
      # the Ruby `end` keyword — but the wire payload uses `"end"`.
      def create_event(summary:, start:, end_time: nil, **rest)
        # Backward-compat: accept `:end` if callers pass it via a hash splat.
        end_time = rest.delete(:end) if end_time.nil? && rest.key?(:end)

        params = {
          "summary" => summary,
          "start" => start,
          "end" => end_time
        }
        params["calendarId"] = rest[:calendar_id] if rest[:calendar_id]
        params["description"] = rest[:description] if rest[:description]
        params["location"] = rest[:location] if rest[:location]
        params["attendees"] = rest[:attendees] if rest[:attendees]
        call("create-event", params)
      end

      def get_event(event_id, calendar_id: nil)
        params = { "eventId" => event_id }
        params["calendarId"] = calendar_id unless calendar_id.nil?
        call("get-event", params)
      end
    end
  end
end
