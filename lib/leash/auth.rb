# frozen_string_literal: true

require "jwt"
require_relative "errors"

module Leash
  # Raised when authentication fails (missing cookie, invalid/expired token, etc.)
  class AuthError < Error
    def initialize(message = "Authentication failed")
      super(message, code: "auth_error")
    end
  end

  # Simple value object representing an authenticated Leash user.
  class User
    attr_reader :id, :email, :name, :picture

    # @param id [String]
    # @param email [String]
    # @param name [String, nil]
    # @param picture [String, nil]
    def initialize(id:, email:, name: nil, picture: nil)
      @id = id
      @email = email
      @name = name
      @picture = picture
    end

    def ==(other)
      other.is_a?(User) &&
        id == other.id &&
        email == other.email &&
        name == other.name &&
        picture == other.picture
    end
  end

  # Framework-agnostic server auth helper.
  #
  # Works with any request object that exposes either:
  #   - request.cookies (Hash) — Rack / Rails / Sinatra
  #   - request.env['HTTP_COOKIE'] or request.get_header('HTTP_COOKIE') — raw Rack env
  #
  # Does NOT require rails, sinatra, or rack.
  module Auth
    COOKIE_NAME = "leash-auth"

    module_function

    # Read the leash-auth JWT from the request, decode it, and return a {Leash::User}.
    #
    # @param request [#cookies, #env, #get_header] any Rack-like request object
    # @return [Leash::User]
    # @raise [Leash::AuthError] when the cookie is missing or the token is invalid/expired
    def get_user(request)
      token = extract_token(request)
      raise AuthError, "Missing leash-auth cookie" if token.nil? || token.empty?

      payload = decode_token(token)
      build_user(payload)
    end

    # Check whether the request carries a valid leash-auth cookie.
    #
    # @param request [#cookies, #env, #get_header]
    # @return [Boolean]
    def authenticated?(request)
      get_user(request)
      true
    rescue AuthError
      false
    end

    # @api private
    def extract_token(request)
      # Strategy 1: request.cookies hash (Rack / Rails / Sinatra)
      if request.respond_to?(:cookies)
        cookies = request.cookies
        if cookies.is_a?(Hash)
          value = cookies[COOKIE_NAME] || cookies[COOKIE_NAME.to_sym]
          return value if value
        end
      end

      # Strategy 2: raw Cookie header from env or get_header
      raw = nil
      if request.respond_to?(:env) && request.env.is_a?(Hash)
        raw = request.env["HTTP_COOKIE"]
      end
      if raw.nil? && request.respond_to?(:get_header)
        begin
          raw = request.get_header("HTTP_COOKIE")
        rescue StandardError
          nil
        end
      end

      parse_cookie_header(raw) if raw
    end

    # @api private
    def parse_cookie_header(header)
      return nil if header.nil?

      header.split(";").each do |pair|
        key, value = pair.strip.split("=", 2)
        return value if key == COOKIE_NAME
      end
      nil
    end

    # @api private
    def decode_token(token)
      secret = ENV["LEASH_JWT_SECRET"]
      if secret && !secret.empty?
        decoded = JWT.decode(token, secret, true, algorithms: ["HS256"])
      else
        decoded = JWT.decode(token, nil, false)
      end
      decoded.first
    rescue JWT::ExpiredSignature
      raise AuthError, "Token has expired"
    rescue JWT::DecodeError => e
      raise AuthError, "Invalid token: #{e.message}"
    end

    # @api private
    def build_user(payload)
      id = payload["id"] || payload["sub"]
      email = payload["email"]
      raise AuthError, "Token payload missing required fields (id/sub, email)" unless id && email

      User.new(
        id: id,
        email: email,
        name: payload["name"],
        picture: payload["picture"]
      )
    end
  end
end
