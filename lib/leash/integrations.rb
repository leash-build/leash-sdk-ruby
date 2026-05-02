# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

require_relative "errors"
require_relative "custom_integration"
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
    # @param api_key [String, nil] optional API key for server-to-server auth
    def initialize(auth_token:, platform_url: DEFAULT_PLATFORM_URL, api_key: nil)
      @auth_token = auth_token
      @platform_url = platform_url.chomp("/")
      @api_key = api_key || ENV["LEASH_API_KEY"]
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

    # Access a custom integration by name. Returns an untyped client.
    #
    # @param name [String] the custom integration name
    # @return [CustomIntegration]
    #
    # @example
    #   stripe = client.integration("stripe")
    #   charges = stripe.call("/v1/charges", method: "GET")
    def integration(name)
      CustomIntegration.new(name, method(:call_custom))
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
      request["X-API-Key"] = @api_key if @api_key
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
      request["X-API-Key"] = @api_key if @api_key

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

    # Get the user's current access token for a provider -- built-in or
    # org-registered (LEA-142). Lets you call third-party APIs directly
    # without proxying every request through Leash. Refresh-on-expiry
    # happens transparently on the platform side.
    #
    # @param provider [String] the provider slug (e.g. "slack", "gmail")
    # @return [String] the access token
    # @raise [Leash::NotConnectedError] if the user hasn't completed the OAuth flow
    # @raise [Leash::TokenExpiredError] if the token is expired and cannot be refreshed
    # @raise [Leash::Error] if the platform returns a non-success response
    def get_access_token(provider)
      uri = URI("#{@platform_url}/api/integrations/token")

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@auth_token}" if @auth_token
      request["X-API-Key"] = @api_key if @api_key
      request.body = { provider: provider }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      data = JSON.parse(response.body)

      unless data["success"]
        raise_error(data)
      end

      data["data"]["accessToken"]
    end

    # Get the resolved config for a customer-registered MCP server (LEA-143).
    # Returns the customer's MCP URL plus auth headers (e.g. +Authorization:
    # Bearer ...+ for bearer-auth servers) -- feed this directly into your
    # MCP client. Leash isn't on the MCP request path.
    #
    # @param slug [String] the MCP server slug
    # @return [Hash] hash with "slug", "displayName", "url", and "headers"
    # @raise [Leash::Error] if the platform returns a non-success response
    #   (e.g. code +unknown_mcp_server+)
    def get_custom_mcp_config(slug)
      uri = URI("#{@platform_url}/api/integrations/mcp-config/#{URI.encode_www_form_component(slug)}")

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@auth_token}" if @auth_token
      request["X-API-Key"] = @api_key if @api_key

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      data = JSON.parse(response.body)

      unless data["success"]
        raise_error(data)
      end

      data["data"]
    end

    # Call any MCP server tool directly.
    #
    # @param package_name [String] the npm package name of the MCP server
    # @param tool [String] the tool name to invoke
    # @param args [Hash] optional arguments to pass to the tool
    # @return [Object] the "data" field from the platform response
    # @raise [Leash::Error] if the platform returns a non-success response
    def mcp(package_name, tool, args = {})
      uri = URI("#{@platform_url}/api/mcp/run")

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@auth_token}" if @auth_token
      request["X-API-Key"] = @api_key if @api_key

      payload = { package: package_name, tool: tool }
      payload[:args] = args unless args.nil? || args.empty?
      request.body = payload.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      data = JSON.parse(response.body)

      unless data["success"]
        raise_error(data)
      end

      data["data"]
    end

    # Fetch env vars from the platform. Cached after first call.
    #
    # @param key [String, nil] optional key to look up
    # @return [Hash, String, nil] all env vars as a Hash, or a single value if key given
    # @raise [Leash::Error] if the platform returns a non-success response
    def get_env(key = nil)
      @env_cache ||= begin
        uri = URI("#{@platform_url}/api/apps/env")

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{@auth_token}" if @auth_token
        request["X-API-Key"] = @api_key if @api_key

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(request)
        end

        data = JSON.parse(response.body)

        unless data["success"]
          raise_error(data)
        end

        data["data"] || {}
      end

      key ? @env_cache[key] : @env_cache
    end

    private

    # Call the custom integration proxy endpoint.
    #
    # @param name [String] the custom integration name
    # @param path [String] the endpoint path to forward
    # @param method [String] HTTP method
    # @param body [Hash, nil] optional JSON body to forward
    # @param headers [Hash, nil] optional extra headers to forward
    # @return [Object] the "data" field from the platform response
    # @raise [Leash::Error] if the platform returns a non-success response
    def call_custom(name, path, method = "GET", body = nil, headers = nil)
      uri = URI("#{@platform_url}/api/integrations/custom/#{name}")

      payload = { path: path, method: method }
      payload[:body] = body if body
      payload[:headers] = headers if headers

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@auth_token}"
      request["X-API-Key"] = @api_key if @api_key
      request.body = payload.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      data = JSON.parse(response.body)

      unless data["success"]
        raise_error(data)
      end

      data["data"]
    end

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
