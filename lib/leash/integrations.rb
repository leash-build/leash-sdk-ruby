# frozen_string_literal: true

require_relative "integrations/base"
require_relative "integrations/gmail"
require_relative "integrations/calendar"
require_relative "integrations/drive"
require_relative "integrations/linear"

module Leash
  module Integrations
    # `leash.integrations` — typed provider namespaces plus a generic
    # `.provider(name)` escape hatch for un-typed providers (Slack, GitHub,
    # HubSpot, Jira, …). Mirrors the TS `leash.integrations` namespace and
    # the Python `IntegrationsNamespace`.
    #
    # Method aliases keep the TS provider names addressable:
    #
    #   leash.integrations.calendar         # canonical (matches TS shape)
    #   leash.integrations.google_calendar  # alias for calendar
    #   leash.integrations.drive            # canonical
    #   leash.integrations.google_drive     # alias for drive
    class Namespace
      def initialize(transport)
        @transport = transport
        @gmail = Gmail.new(transport)
        @calendar = Calendar.new(transport)
        @drive = Drive.new(transport)
        @linear = Linear.new(transport)
      end

      attr_reader :gmail, :calendar, :drive, :linear

      # Aliases matching the Google-prefixed provider IDs (and platform
      # docs that use them). Same instances as `calendar` / `drive`.
      alias google_calendar calendar
      alias google_drive drive

      # Generic escape hatch — `leash.integrations.provider('slack').call(...)`.
      def provider(name)
        Caller.new(@transport, name)
      end
    end
  end
end
