# frozen_string_literal: true

require "jwt"
require_relative "errors"
require_relative "types"

module Leash
  # Cookie + Bearer-token + JWT extraction across Ruby web frameworks.
  #
  # Mirrors the multi-framework strategy in `leash-sdk-ts/src/server/auth.ts`
  # and `leash-sdk-python/leash/auth.py`. Designed to never raise during
  # extraction — `extract_cookie` / `extract_bearer_token` return `nil` on
  # any unexpected request shape so callers can branch cleanly.
  #
  # Supported request shapes (0.4):
  #   * Rack hash (`{"rack.input" => …, "HTTP_COOKIE" => …}`)
  #   * Rails `ActionDispatch::Request` (`request.cookies`, `request.headers`)
  #   * Sinatra `Sinatra::Request` (`request.cookies`, `request.env`)
  #   * Hanami request (responds to `:get_header`)
  #   * Anything quacking with `.cookies` / `.env` / `.headers` / `.get_header`
  #
  # Does NOT require rails, sinatra, rack, or hanami — only stdlib + jwt.
  module Auth
    COOKIE_NAME = "leash-auth"
    AUTH_HEADER = "authorization"

    module_function

    # ------------------------------------------------------------------
    # Public helpers (kept stable from 0.3)
    # ------------------------------------------------------------------

    # Decode the request's leash-auth cookie into a {Leash::User}.
    #
    # @raise [Leash::AuthError] when the cookie is missing / invalid / expired.
    def get_user(request)
      token = extract_cookie(request)
      raise AuthError, "Missing leash-auth cookie" if token.nil? || token.empty?

      payload = decode_token(token)
      build_user(payload)
    end

    # True when {get_user} would return a user.
    def authenticated?(request)
      get_user(request)
      true
    rescue AuthError
      false
    end

    # ------------------------------------------------------------------
    # Extraction primitives
    # ------------------------------------------------------------------

    # Return the named cookie value off any request shape, or `nil`.
    # Never raises — returns `nil` on unexpected shapes.
    def extract_cookie(request, name = COOKIE_NAME)
      return nil if request.nil?

      from_cookie_jar(request, name) || from_cookie_header(request, name)
    rescue StandardError
      nil
    end

    # Backwards-compat alias for the 0.3 internal method name.
    def extract_token(request)
      extract_cookie(request)
    end

    # Return the JWT off `Authorization: Bearer …` if present, else `nil`.
    # Never raises.
    def extract_bearer_token(request)
      return nil if request.nil?

      raw = header_lookup(request, AUTH_HEADER)
      return nil unless raw.is_a?(String)

      parts = raw.split(/\s+/, 2)
      return nil unless parts.length == 2

      scheme, token = parts
      return nil unless scheme.downcase == "bearer"

      stripped = token.strip
      return nil if stripped.empty?

      stripped
    rescue StandardError
      nil
    end

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    # @api private
    def from_cookie_jar(request, name)
      return nil unless request.respond_to?(:cookies)

      cookies = request.cookies
      return nil if cookies.nil?

      if cookies.respond_to?(:[])
        value = nil
        begin
          value = cookies[name]
        rescue StandardError
          value = nil
        end
        if value.nil? && cookies.respond_to?(:fetch)
          begin
            value = cookies.fetch(name.to_sym, nil)
          rescue StandardError
            value = nil
          end
        end
        normalised = normalise_cookie_value(value)
        return normalised unless normalised.nil?
      end

      nil
    end

    # @api private
    def from_cookie_header(request, name)
      raw = nil

      if request.respond_to?(:env)
        env = begin
          request.env
        rescue StandardError
          nil
        end
        if env.is_a?(Hash)
          raw = env["HTTP_COOKIE"] || env["rack.cookie"] || env["cookie"]
        end
      end

      if raw.nil? && request.is_a?(Hash)
        raw = request["HTTP_COOKIE"] ||
              request["rack.cookie"] ||
              request["cookie"] ||
              request[:cookie]
      end

      if raw.nil?
        raw = header_lookup(request, "cookie")
      end

      return nil unless raw.is_a?(String) && !raw.empty?

      parse_cookie_header(raw, name)
    end

    # @api private
    def parse_cookie_header(header, name = COOKIE_NAME)
      return nil if header.nil?

      header.split(";").each do |pair|
        k, v = pair.strip.split("=", 2)
        next unless k == name

        return v.nil? ? nil : v
      end
      nil
    end

    # @api private
    def normalise_cookie_value(value)
      return nil if value.nil?
      return value if value.is_a?(String) && !value.empty?
      return value.value if value.respond_to?(:value) && value.value.is_a?(String)

      begin
        candidate = value["value"]
        return candidate if candidate.is_a?(String) && !candidate.empty?
      rescue StandardError
        nil
      end
      nil
    end

    # @api private
    # Case-insensitive header lookup against any mapping or headers-like object.
    def header_lookup(request, name)
      lname = name.downcase

      # Direct `headers` accessor (Rails / Rack / Hanami)
      if request.respond_to?(:headers)
        h = begin
          request.headers
        rescue StandardError
          nil
        end
        if h
          # Try common variants
          [name, lname, "HTTP_#{name.upcase.tr('-', '_')}"].each do |key|
            begin
              val = h[key]
              return val if val.is_a?(String) && !val.empty?
            rescue StandardError
              next
            end
          end
          if h.respond_to?(:each)
            begin
              h.each do |k, v|
                return v if k.respond_to?(:downcase) && k.downcase == lname && v.is_a?(String)
              end
            rescue StandardError
              # fall through
            end
          end
        end
      end

      # `get_header` accessor (Rack::Request / Hanami)
      if request.respond_to?(:get_header)
        begin
          val = request.get_header("HTTP_#{name.upcase.tr('-', '_')}")
          return val if val.is_a?(String) && !val.empty?
        rescue StandardError
          # ignore
        end
        begin
          val = request.get_header(name)
          return val if val.is_a?(String) && !val.empty?
        rescue StandardError
          # ignore
        end
      end

      # Raw `env` hash (Rack)
      if request.respond_to?(:env)
        env = begin
          request.env
        rescue StandardError
          nil
        end
        if env.is_a?(Hash)
          val = env["HTTP_#{name.upcase.tr('-', '_')}"]
          return val if val.is_a?(String) && !val.empty?
        end
      end

      # Caller passed a plain Hash of headers / env directly
      if request.is_a?(Hash)
        ["HTTP_#{name.upcase.tr('-', '_')}", name, lname, name.capitalize].each do |key|
          val = request[key]
          return val if val.is_a?(String) && !val.empty?
        end
      end

      nil
    end

    # @api private
    def decode_token(token)
      secret = ENV["LEASH_JWT_SECRET"]
      decoded = if secret && !secret.empty?
                  JWT.decode(token, secret, true, algorithms: ["HS256"])
                else
                  JWT.decode(token, nil, false)
                end
      decoded.first
    rescue JWT::ExpiredSignature
      raise AuthError, "Token has expired"
    rescue JWT::DecodeError => e
      raise AuthError, "Invalid token: #{e.message}"
    end

    # @api private
    def build_user(payload)
      id = payload["id"] || payload["sub"] || payload["userId"]
      email = payload["email"]
      raise AuthError, "Token payload missing required fields (id/sub, email)" unless id && email

      User.new(
        id: id.to_s,
        email: email,
        name: payload["name"],
        picture: payload["picture"]
      )
    end
  end
end
