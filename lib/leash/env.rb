# frozen_string_literal: true

require "cgi"

require_relative "errors"

module Leash
  # `leash.env` namespace — runtime env-var fetcher with a per-instance
  # 60 s TTL cache. Mirrors the TS `leash.env.get` / `leash.env.getMany`
  # surface and the Python `EnvNamespace` behaviour (`Optional[str]` — Ruby
  # returns `nil` for HTTP 404 instead of raising, so callers can branch
  # naturally).
  class Env
    CACHE_TTL_S = 60

    attr_reader :platform_url

    def initialize(platform_url:, api_key:, transport:)
      @platform_url = platform_url.to_s.sub(%r{/+\z}, "")
      @api_key = api_key
      @transport = transport
      @cache = {}
    end

    # Resolve a single env-var value.
    #
    # @param key [String] the env-var name (uppercase by convention)
    # @param fresh [Boolean] skip the TTL cache for this call; the freshly
    #   fetched value is still written back to the cache
    # @return [String, nil] the value, or `nil` when the platform reports the
    #   key as not declared / not found
    # @raise [Leash::Error] for auth / invalid-key / plan / platform errors
    def get(key, fresh: false)
      now = monotonic_now
      unless fresh
        entry = @cache[key]
        return entry[:value] if entry && entry[:expires_at] > now
      end

      value = fetch_one(key)
      @cache[key] = { value: value, expires_at: now + CACHE_TTL_S }
      value
    end

    # Bulk variant — resolve multiple keys sequentially against the shared
    # TTL cache.
    #
    # @return [Hash{String => String, nil}]
    def get_many(keys)
      result = {}
      keys.each { |k| result[k] = get(k) }
      result
    end

    # @api private — for tests / introspection.
    def clear_cache!
      @cache.clear
    end

    private

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def fetch_one(key)
      raise NoApiKeyError unless @api_key

      # Use path-style percent-encoding (TS `encodeURIComponent` semantics):
      # spaces become %20, not + (CGI.escape's form-encoding default).
      encoded = CGI.escape(key).gsub("+", "%20")
      url = "#{@platform_url}/api/apps/me/secrets/#{encoded}"

      # Env reads use `Authorization: Bearer <api_key>` — matches the platform
      # contract for /api/apps/me/secrets/[key] (see leash.ts line 299 + 303).
      response = @transport.get_json(url, headers: {
        "Authorization" => "Bearer #{@api_key}"
      })

      status = response.respond_to?(:code) ? response.code.to_i : 0
      body = parse_json(response.respond_to?(:body) ? response.body : nil)

      case status
      when 400
        raise Error.new(
          "Invalid env-var key: '#{key}'.",
          code: "INVALID_KEY",
          action: "Env-var names must match /^[A-Za-z_][A-Za-z0-9_]*$/ and be no longer than 100 characters.",
          see_also: "https://leash.build/docs/sdk",
          status: 400
        )
      when 401
        raise UnauthorizedError.new(
          "Missing or invalid LEASH_API_KEY.",
          action: "Mint a fresh API key at /dashboard/organization.",
          see_also: "https://leash.build/dashboard/organization",
          status: 401
        )
      when 402
        required_plan = body.is_a?(Hash) ? body["requiredPlan"] : nil
        suffix = required_plan ? " (requiredPlan: #{required_plan})" : ""
        raise UpgradeRequiredError.new(
          "leash.env.get requires the Growth plan or above#{suffix}.",
          action: "Upgrade at https://leash.build/dashboard/billing.",
          see_also: "https://leash.build/dashboard/billing",
          status: 402
        )
      when 404
        # Ruby idiom: return nil for missing keys instead of raising so
        # callers can branch with `if value.nil?`. Mirrors Python.
        return nil
      when 502
        platform_error = body.is_a?(Hash) ? body["error"] : nil
        raise Error.new(
          platform_error || "Secret source resync failed on the platform side.",
          code: "SOURCE_RESYNC_FAILED",
          action: "Check your secret source configuration in the Leash dashboard.",
          see_also: "https://leash.build/dashboard",
          status: 502
        )
      end

      if status >= 400
        raise Error.new(
          "Unexpected response from platform: HTTP #{status}",
          code: "ENV_FETCH_ERROR",
          action: "Check the Leash platform status and your configuration.",
          see_also: "https://leash.build/docs/sdk",
          status: status
        )
      end

      value = body.is_a?(Hash) ? body["value"] : nil
      unless value.is_a?(String)
        raise Error.new(
          "Platform returned an unexpected response shape for key '#{key}'.",
          code: "ENV_FETCH_ERROR",
          action: "Check the Leash platform status and your configuration.",
          see_also: "https://leash.build/docs/sdk",
          status: status
        )
      end
      value
    end

    def parse_json(body)
      return nil if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    class NoApiKeyError < Error
      def initialize
        super(
          "LEASH_API_KEY is required to call leash.env.get().",
          code: "NO_API_KEY",
          action: "Set LEASH_API_KEY in your environment or pass api_key: ... to Leash.new.",
          see_also: "https://leash.build/dashboard/organization"
        )
      end
    end
  end
end
