# frozen_string_literal: true

require_relative "base"

module Leash
  module Integrations
    # `leash.integrations.gmail` — mirrors TS `leash.integrations.gmail`.
    class Gmail < Base
      PROVIDER = "gmail"

      # @param query [String, nil] Gmail search query
      # @param max_results [Integer, nil]
      # @param label_ids [Array<String>, nil]
      # @param page_token [String, nil]
      def list_messages(query: nil, max_results: nil, label_ids: nil, page_token: nil)
        params = compact_params(
          "query" => query,
          "maxResults" => max_results,
          "labelIds" => label_ids,
          "pageToken" => page_token
        )
        call("list-messages", params.empty? ? nil : params)
      end

      # @param message_id [String]
      # @param format ['full','metadata','minimal','raw']
      def get_message(message_id, format: "full")
        call("get-message", { "messageId" => message_id, "format" => format })
      end

      # @param to [String]
      # @param subject [String]
      # @param body [String]
      # @param cc [String, nil]
      # @param bcc [String, nil]
      def send_message(to:, subject:, body:, cc: nil, bcc: nil)
        params = compact_params(
          "to" => to, "subject" => subject, "body" => body, "cc" => cc, "bcc" => bcc
        )
        call("send-message", params)
      end

      # @param query [String]
      # @param max_results [Integer, nil]
      def search_messages(query, max_results: nil)
        params = { "query" => query }
        params["maxResults"] = max_results unless max_results.nil?
        call("search-messages", params)
      end

      def list_labels
        call("list-labels")
      end

      def get_profile
        call("get-profile")
      end
    end
  end
end
