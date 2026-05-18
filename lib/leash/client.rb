# frozen_string_literal: true

require_relative "auth"
require_relative "env"
require_relative "errors"
require_relative "integrations"
require_relative "transport"
require_relative "types"

module Leash
  DEFAULT_PLATFORM_URL = "https://leash.build"

  # Unified Leash client — namespaces for `auth`, `env`, `integrations`.
  # Ruby mirror of `leash-sdk-ts/src/leash.ts` and `leash-sdk-python/leash/client.py`.
  #
  # Construction is server-only in 0.4 and requires a request object:
  #
  #   leash = Leash.new(request: request)        # Rails / Sinatra / Hanami / Rack hash
  #   user = leash.auth.user                     # Leash::User or nil
  #   key  = leash.env.get("OPENAI_API_KEY")     # String or nil
  #   msgs = leash.integrations.gmail.list_messages(max_results: 5)
  #
  # Authentication precedence (mirror TS / Python / Go exactly):
  #
  #   1. `LEASH_API_KEY` env var (or explicit `api_key:` constructor arg)
  #   2. `Authorization: Bearer <jwt>` header on the request — used for
  #      `auth.user` AND as an env-read fallback (when no API key), but
  #      NEVER forwarded on integration POSTs
  #   3. `leash-auth` cookie from the request
  #
  # The Bearer fallback for env reads is documented here per the Go-reviewer
  # callout: when the constructor sees no `LEASH_API_KEY` but does see an
  # inbound `Authorization: Bearer …`, the bearer JWT is used as the API key
  # for the platform's `/api/apps/me/secrets/[key]` endpoint. The bearer is
  # still suppressed on integration POSTs (Critical #1 in the 0.4 plan).
  class Client
    # @return [Leash::Integrations::Namespace]
    attr_reader :integrations

    # @return [Leash::Env]
    attr_reader :env

    # @return [Auth]
    attr_reader :auth

    # @return [String]
    attr_reader :platform_url

    # @param request [Object, Hash] any Rack-conforming request (Rails
    #   `ActionDispatch::Request`, Sinatra `Sinatra::Request`, Hanami,
    #   a plain Rack `env` hash, or anything quacking with `.cookies` / `.env`).
    # @param platform_url [String, nil] override the platform base URL.
    #   Defaults to `LEASH_PLATFORM_URL` env var or `https://leash.build`.
    # @param api_key [String, nil] explicit `LEASH_API_KEY` override.
    # @param transport [Leash::Transport, nil] inject a transport (handy for
    #   tests). When omitted, a default `Net::HTTP`-backed transport is built.
    def initialize(request:, platform_url: nil, api_key: nil, transport: nil)
      if request.nil?
        raise Error.new(
          "Leash requires a request object in server environments.",
          code: "NO_REQUEST_SERVER_CONSTRUCT",
          action: "Pass request: req to Leash.new in your route handler.",
          see_also: "https://leash.build/docs/sdk"
        )
      end

      @request = request
      @platform_url = (platform_url || ENV["LEASH_PLATFORM_URL"] || DEFAULT_PLATFORM_URL)
                      .to_s.sub(%r{/+\z}, "")

      # Auth precedence: explicit api_key > LEASH_API_KEY env > bearer header > cookie.
      env_api_key = ENV["LEASH_API_KEY"]
      env_api_key = nil if env_api_key && env_api_key.empty?
      @explicit_api_key = api_key || env_api_key

      @bearer_token = Auth.extract_bearer_token(request)
      @cookie_value = Auth.extract_cookie(request)

      # Bearer→env fallback: when no app key is present, the inbound user
      # JWT is used to authenticate env reads to the platform. NEVER used
      # as `X-API-Key` on integration POSTs (see Transport docstring).
      @env_api_key = @explicit_api_key || @bearer_token

      @transport = transport || Transport.new(
        platform_url: @platform_url,
        api_key: @explicit_api_key,
        cookie_value: @cookie_value
      )

      @auth = AuthFacade.new(request)
      @env = Env.new(
        platform_url: @platform_url,
        api_key: @env_api_key,
        transport: @transport
      )
      @integrations = Integrations::Namespace.new(@transport)
    end

    # @api private — exposed so tests can introspect resolved credentials.
    attr_reader :bearer_token, :cookie_value, :explicit_api_key

    # `leash.auth` — sync, non-throwing wrapper around {Leash::Auth.get_user}.
    class AuthFacade
      def initialize(request)
        @request = request
      end

      # @return [Leash::User, nil] the authenticated user, or `nil` when not
      #   authenticated. Never raises — swallows decode errors so handlers can
      #   branch with a clean `if user.nil?`.
      def user
        Leash::Auth.get_user(@request)
      rescue Leash::AuthError
        nil
      rescue StandardError
        nil
      end

      # @return [Boolean]
      def authenticated?
        !user.nil?
      end
    end
  end

  # `Leash.new(...)` is the idiomatic Ruby entry point. We delegate to
  # `Client.new` so the module-level constant `Leash` stays a module
  # (necessary because `Leash::Auth`, `Leash::Error`, etc. all live under it).
  def self.new(**kwargs)
    Client.new(**kwargs)
  end
end
