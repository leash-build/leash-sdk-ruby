# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

require_relative "errors"
require_relative "gmail"
require_relative "calendar"
require_relative "drive"

module Leash
  DEFAULT_PLATFORM_URL = "https://leash.build"

  # Main client for accessing Leash platform integrations.
  #
  # @example
  #   client = Leash::Integrations.new(auth_token: "your-jwt-token")
  #   messages = client.gmail.list_messages(query: "is:unread")
  #   events = client.calendar.list_events(time_min: "2026-04-10T00:00:00Z")
  #   files = client.drive.list_files
  class Integrations
    # @param auth_token [String] the leash-auth JWT token
    # @param platform_url [String] base URL of the Leash platform API
    def initialize(auth_token:, platform_url: DEFAULT_PLATFORM_URL)
      @auth_token = auth_token
      @platform_url = platform_url.chomp("/")
    end

    # Gmail integration client.
    #
    # @return [GmailClient]
    def gmail
      @gmail ||= GmailClient.new(method(:call))
    end

    # Google Calendar integration client.
    #
    # @return [CalendarClient]
    def calendar
      @calendar ||= CalendarClient.new(method(:call))
    end

    # Google Drive integration client.
    #
    # @return [DriveClient]
    def drive
      @drive ||= DriveClient.new(method(:call))
    end

    # Generic proxy call for any provider action.
    #
    # @param provider [String] integration provider name (e.g. "gmail")
    # @param action [String] action to perform (e.g. "list-messages")
    # @param params [Hash, nil] optional request body parameters
    # @return [Object] the "data" field from the platform response
    # @raise [Leash::NotConnectedError] if the provider is not connected
    # @raise [Leash::TokenExpiredError] if the OAuth token has expired
    # @raise [Leash::Error] if the platform returns a non-success response
    def call(provider, action, params = nil)
      uri = URI("#{@platform_url}/api/integrations/#{provider}/#{action}")

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@auth_token}"
      request.body = (params || {}).to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      data = JSON.parse(response.body)

      unless data["success"]
        raise_error(data)
      end

      data["data"]
    end

    # Check if a provider is connected for the current user.
    #
    # @param provider_id [String] the provider identifier (e.g. "gmail")
    # @return [Boolean]
    def connected?(provider_id)
      conn = connections.find { |c| c["providerId"] == provider_id }
      conn&.dig("status") == "active"
    rescue StandardError
      false
    end

    # Get connection status for all providers.
    #
    # @return [Array<Hash>] list of connection status hashes
    def connections
      uri = URI("#{@platform_url}/api/integrations/connections")

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@auth_token}"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      data = JSON.parse(response.body)

      unless data["success"]
        raise_error(data)
      end

      data["data"] || []
    end

    # Get the URL to connect a provider (for UI buttons).
    #
    # @param provider_id [String] the provider identifier
    # @param return_url [String, nil] optional URL to redirect back to after connecting
    # @return [String] the full URL to initiate the OAuth connection flow
    def connect_url(provider_id, return_url: nil)
      url = "#{@platform_url}/api/integrations/connect/#{provider_id}"
      url += "?return_url=#{URI.encode_www_form_component(return_url)}" if return_url
      url
    end

    private

    # Map error codes to specific exception classes.
    #
    # @param data [Hash] the parsed error response
    # @raise [Leash::NotConnectedError, Leash::TokenExpiredError, Leash::Error]
    def raise_error(data)
      message = data["error"] || "Unknown error"
      code = data["code"]
      connect_url = data["connectUrl"]

      case code
      when "not_connected"
        raise NotConnectedError.new(message, connect_url: connect_url)
      when "token_expired"
        raise TokenExpiredError.new(message, connect_url: connect_url)
      else
        raise Error.new(message, code: code, connect_url: connect_url)
      end
    end
  end
end
