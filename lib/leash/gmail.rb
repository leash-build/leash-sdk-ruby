# frozen_string_literal: true

module Leash
  # Client for Gmail operations via the Leash platform proxy.
  #
  # Not instantiated directly -- use {Integrations#gmail} instead.
  class GmailClient
    PROVIDER = "gmail"

    # @api private
    def initialize(call_fn)
      @call = call_fn
    end

    # List messages in the user's mailbox.
    #
    # @param query [String, nil] Gmail search query (e.g. "from:user@example.com")
    # @param max_results [Integer] maximum number of messages to return
    # @param label_ids [Array<String>, nil] filter by label IDs (e.g. ["INBOX"])
    # @param page_token [String, nil] token for fetching the next page of results
    # @return [Hash] hash with "messages", "nextPageToken", and "resultSizeEstimate"
    def list_messages(query: nil, max_results: 20, label_ids: nil, page_token: nil)
      params = { "maxResults" => max_results }
      params["query"] = query if query
      params["labelIds"] = label_ids if label_ids
      params["pageToken"] = page_token if page_token
      @call.call(PROVIDER, "list-messages", params)
    end

    # Get a single message by ID.
    #
    # @param message_id [String] the message ID
    # @param format [String] response format ("full", "metadata", "minimal", "raw")
    # @return [Hash] the full message object
    def get_message(message_id, format: "full")
      @call.call(PROVIDER, "get-message", { "messageId" => message_id, "format" => format })
    end

    # Send an email message.
    #
    # @param to [String] recipient email address
    # @param subject [String] email subject line
    # @param body [String] email body text
    # @param cc [String, nil] CC recipient(s)
    # @param bcc [String, nil] BCC recipient(s)
    # @return [Hash] the sent message metadata
    def send_message(to:, subject:, body:, cc: nil, bcc: nil)
      params = { "to" => to, "subject" => subject, "body" => body }
      params["cc"] = cc if cc
      params["bcc"] = bcc if bcc
      @call.call(PROVIDER, "send-message", params)
    end

    # Search messages using a Gmail query string.
    #
    # @param query [String] Gmail search query
    # @param max_results [Integer] maximum number of results to return
    # @return [Hash] hash with "messages", "nextPageToken", and "resultSizeEstimate"
    def search_messages(query, max_results: 20)
      @call.call(PROVIDER, "search-messages", { "query" => query, "maxResults" => max_results })
    end

    # List all labels in the user's mailbox.
    #
    # @return [Hash] hash with "labels" list
    def list_labels
      @call.call(PROVIDER, "list-labels", {})
    end
  end
end
