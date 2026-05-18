# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require_relative "errors"

module Leash
  # @api private
  #
  # Shared HTTP transport used by every integration POST. Mirrors the
  # `_call` / `_post` private methods on the TS `Leash` class and the
  # Python `_Transport`.
  #
  # Critical platform contract (Critical #1 in the 0.4 plan):
  #
  #   * `X-API-Key` carries the app key (`LEASH_API_KEY`)
  #   * `Cookie: leash-auth=…` forwards the browser session
  #
  # The user JWT extracted from an inbound `Authorization: Bearer …` header is
  # intentionally NOT forwarded — the TS SDK warns that the JWT path causes
  # the platform's `verifyToken()` to reject before the X-API-Key check runs,
  # producing a misleading 401 on every integration call. Bearer tokens are
  # still accepted by `Leash` for other code paths (env.get fallback, future
  # CLI flows) but never sent on integration POSTs. A negative-assertion test
  # covers this.
  class Transport
    DEFAULT_OPEN_TIMEOUT = 10
    DEFAULT_READ_TIMEOUT = 30

    attr_reader :platform_url, :api_key, :cookie_value

    def initialize(platform_url:, api_key: nil, cookie_value: nil,
                   open_timeout: DEFAULT_OPEN_TIMEOUT,
                   read_timeout: DEFAULT_READ_TIMEOUT,
                   http_runner: nil)
      @platform_url = platform_url.to_s.sub(%r{/+\z}, "")
      @api_key = api_key
      @cookie_value = cookie_value
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      # Test seam — allow injecting a custom HTTP runner block.
      # If nil, calls go through `Net::HTTP.start`.
      @http_runner = http_runner
    end

    # POST to `/api/integrations/{provider}/{action}` and return the parsed
    # response body (after unwrapping `{success, data}`).
    def call(provider, action, params = nil)
      url = "#{@platform_url}/api/integrations/#{provider}/#{action}"
      docs_url = "https://leash.build/docs/integrations/#{provider}"
      post_json(url, params, docs_url: docs_url)
    end

    # @api private — used by env.rb for GET /api/apps/me/secrets/<key>.
    def get_json(url, headers: {})
      run_request(url, method: :get, headers: headers, body: nil)
    end

    # @api private — used by env.rb for arbitrary URLs.
    def post_json(url, params, docs_url:)
      headers = { "Content-Type" => "application/json" }
      headers["X-API-Key"] = @api_key if @api_key
      headers["Cookie"] = "leash-auth=#{@cookie_value}" if @cookie_value

      body = (params.nil? ? {} : params).to_json
      response = run_request(url, method: :post, headers: headers, body: body)

      handle_response(response, docs_url: docs_url)
    end

    # @api private
    def run_request(url, method:, headers:, body:)
      uri = URI.parse(url)
      request = build_request(uri, method: method, headers: headers, body: body)

      if @http_runner
        return @http_runner.call(uri, request)
      end

      use_ssl = uri.scheme == "https"
      opts = { use_ssl: use_ssl, open_timeout: @open_timeout, read_timeout: @read_timeout }

      Net::HTTP.start(uri.host, uri.port, **opts) do |http|
        http.request(request)
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise NetworkError.new("Timed out reaching the Leash platform: #{e.message}",
                              action: "Check your network connection and that the Leash platform is reachable.",
                              see_also: "https://leash.build/docs/sdk",
                              cause: e)
    rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, IOError => e
      raise NetworkError.new(e.message,
                              action: "Check your network connection and that the Leash platform is reachable.",
                              see_also: "https://leash.build/docs/sdk",
                              cause: e)
    end

    # @api private
    def build_request(uri, method:, headers:, body:)
      request =
        case method
        when :post then Net::HTTP::Post.new(uri.request_uri)
        when :get  then Net::HTTP::Get.new(uri.request_uri)
        else raise ArgumentError, "Unsupported HTTP method: #{method}"
        end

      headers.each { |k, v| request[k] = v }
      request.body = body if body

      request
    end

    # @api private
    def handle_response(response, docs_url:)
      status = response.respond_to?(:code) ? response.code.to_i : 0
      body_raw = response.respond_to?(:body) ? response.body : nil

      parsed = parse_json(body_raw)

      if status >= 400
        raise_for_status(status, parsed, docs_url: docs_url)
      end

      if parsed.is_a?(Hash)
        # Platform contract: { success, data } envelope OR raw shape.
        if parsed["success"] == false
          err_message = parsed["error"].is_a?(String) ? parsed["error"] : "Integration error"
          err_code = parsed["code"].is_a?(String) ? parsed["code"] : "INTEGRATION_ERROR"
          raise Error.new(err_message,
                          code: err_code,
                          action: "Check your integration configuration and try again.",
                          see_also: docs_url,
                          status: status,
                          connect_url: parsed["connectUrl"])
        end
        return parsed["data"] if parsed.key?("data")

        return parsed
      end

      parsed
    end

    # @api private
    def parse_json(body)
      return nil if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    # @api private
    def raise_for_status(status, body, docs_url:)
      message = "HTTP #{status}"
      if body.is_a?(Hash) && body["error"].is_a?(String)
        message = body["error"]
      end

      case status
      when 401
        raise UnauthorizedError.new(message,
                                     action: "Ensure the leash-auth cookie is present, or open your app from the Leash dashboard to get a valid session.",
                                     see_also: "https://leash.build/docs/sdk",
                                     status: status)
      when 402
        msg = (body.is_a?(Hash) && body["message"].is_a?(String) ? body["message"] : message)
        raise UpgradeRequiredError.new(msg,
                                        action: "Upgrade your plan at https://leash.build/dashboard/billing.",
                                        see_also: "https://leash.build/pricing",
                                        status: status)
      when 403
        raise ConnectionRequiredError.new(message,
                                           action: "Connect the integration at /dashboard/integrations and make sure this app is on the allow-list.",
                                           see_also: "https://leash.build/dashboard/integrations",
                                           status: status)
      else
        raise Error.new(message,
                        code: "INTEGRATION_ERROR",
                        action: "Check your integration configuration and try again — the upstream provider returned an error.",
                        see_also: docs_url,
                        status: status)
      end
    end
  end
end
