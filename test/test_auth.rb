# frozen_string_literal: true

require "minitest/autorun"
require "jwt"

require_relative "../lib/leash"

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

USER_PAYLOAD = {
  "id" => "user-123",
  "email" => "alice@example.com",
  "name" => "Alice",
  "picture" => "https://example.com/alice.jpg"
}.freeze

def make_token(payload = USER_PAYLOAD, secret: nil, exp: nil)
  p = payload.dup
  p["exp"] = exp if exp
  if secret
    JWT.encode(p, secret, "HS256")
  else
    JWT.encode(p, nil, "none")
  end
end

# A fake request that exposes a cookies hash (Rack/Rails/Sinatra style).
class FakeRackRequest
  attr_reader :cookies

  def initialize(cookies = {})
    @cookies = cookies
  end
end

# A fake request that exposes env hash only (raw Rack env style).
class FakeEnvRequest
  attr_reader :env

  def initialize(env = {})
    @env = env
  end
end

# A fake request that only supports get_header.
class FakeHeaderRequest
  def initialize(headers = {})
    @headers = headers
  end

  def get_header(name)
    @headers[name]
  end
end

# --------------------------------------------------------------------------
# Tests
# --------------------------------------------------------------------------

class TestLeashAuth < Minitest::Test
  def setup
    @original_secret = ENV["LEASH_JWT_SECRET"]
    ENV.delete("LEASH_JWT_SECRET")
  end

  def teardown
    if @original_secret
      ENV["LEASH_JWT_SECRET"] = @original_secret
    else
      ENV.delete("LEASH_JWT_SECRET")
    end
  end

  # ---- Rack-style request (request.cookies hash) ---------------------------

  def test_get_user_from_cookies_hash
    token = make_token
    request = FakeRackRequest.new("leash-auth" => token)
    user = Leash::Auth.get_user(request)

    assert_instance_of Leash::User, user
    assert_equal "user-123", user.id
    assert_equal "alice@example.com", user.email
    assert_equal "Alice", user.name
    assert_equal "https://example.com/alice.jpg", user.picture
  end

  # ---- Raw env style (request.env['HTTP_COOKIE']) --------------------------

  def test_get_user_from_env_http_cookie
    token = make_token
    request = FakeEnvRequest.new("HTTP_COOKIE" => "other=val; leash-auth=#{token}; foo=bar")
    user = Leash::Auth.get_user(request)

    assert_equal "user-123", user.id
    assert_equal "alice@example.com", user.email
  end

  # ---- get_header fallback -------------------------------------------------

  def test_get_user_from_get_header
    token = make_token
    request = FakeHeaderRequest.new("HTTP_COOKIE" => "leash-auth=#{token}")
    user = Leash::Auth.get_user(request)

    assert_equal "user-123", user.id
  end

  # ---- Missing cookie raises error ----------------------------------------

  def test_missing_cookie_raises_auth_error
    request = FakeRackRequest.new({})
    err = assert_raises(Leash::AuthError) { Leash::Auth.get_user(request) }
    assert_includes err.message, "Missing leash-auth cookie"
  end

  def test_empty_cookie_raises_auth_error
    request = FakeRackRequest.new("leash-auth" => "")
    assert_raises(Leash::AuthError) { Leash::Auth.get_user(request) }
  end

  # ---- Invalid token raises error ------------------------------------------

  def test_invalid_token_raises_auth_error
    request = FakeRackRequest.new("leash-auth" => "not-a-jwt")
    err = assert_raises(Leash::AuthError) { Leash::Auth.get_user(request) }
    assert_includes err.message, "Invalid token"
  end

  # ---- Expired token raises error ------------------------------------------

  def test_expired_token_raises_auth_error
    ENV["LEASH_JWT_SECRET"] = "test-secret"
    token = make_token(secret: "test-secret", exp: Time.now.to_i - 3600)
    request = FakeRackRequest.new("leash-auth" => token)
    err = assert_raises(Leash::AuthError) { Leash::Auth.get_user(request) }
    assert_includes err.message, "expired"
  end

  # ---- No LEASH_JWT_SECRET decodes without verification --------------------

  def test_decode_without_verification_when_no_secret
    ENV.delete("LEASH_JWT_SECRET")
    # Create a token signed with HS256 but decode without verification
    token = JWT.encode(USER_PAYLOAD, "some-secret", "HS256")
    request = FakeRackRequest.new("leash-auth" => token)
    user = Leash::Auth.get_user(request)

    assert_equal "user-123", user.id
    assert_equal "alice@example.com", user.email
  end

  # ---- With LEASH_JWT_SECRET, signature is verified ------------------------

  def test_signature_verified_when_secret_set
    ENV["LEASH_JWT_SECRET"] = "correct-secret"
    token = make_token(secret: "correct-secret")
    request = FakeRackRequest.new("leash-auth" => token)
    user = Leash::Auth.get_user(request)

    assert_equal "user-123", user.id
  end

  def test_wrong_secret_raises_auth_error
    ENV["LEASH_JWT_SECRET"] = "correct-secret"
    token = make_token(secret: "wrong-secret")
    request = FakeRackRequest.new("leash-auth" => token)
    assert_raises(Leash::AuthError) { Leash::Auth.get_user(request) }
  end

  # ---- authenticated? returns true/false -----------------------------------

  def test_authenticated_returns_true
    token = make_token
    request = FakeRackRequest.new("leash-auth" => token)
    assert Leash::Auth.authenticated?(request)
  end

  def test_authenticated_returns_false_missing_cookie
    request = FakeRackRequest.new({})
    refute Leash::Auth.authenticated?(request)
  end

  def test_authenticated_returns_false_invalid_token
    request = FakeRackRequest.new("leash-auth" => "garbage")
    refute Leash::Auth.authenticated?(request)
  end

  # ---- Error hierarchy -----------------------------------------------------

  def test_auth_error_is_leash_error
    assert Leash::AuthError < Leash::Error
    assert Leash::AuthError < StandardError
  end

  # ---- User with sub field instead of id -----------------------------------

  def test_user_from_sub_field
    payload = { "sub" => "user-456", "email" => "bob@example.com" }
    token = make_token(payload)
    request = FakeRackRequest.new("leash-auth" => token)
    user = Leash::Auth.get_user(request)

    assert_equal "user-456", user.id
    assert_equal "bob@example.com", user.email
    assert_nil user.name
    assert_nil user.picture
  end

  # ---- Missing required fields in payload ----------------------------------

  def test_missing_email_raises_auth_error
    token = make_token({ "id" => "user-1" })
    request = FakeRackRequest.new("leash-auth" => token)
    err = assert_raises(Leash::AuthError) { Leash::Auth.get_user(request) }
    assert_includes err.message, "missing required fields"
  end
end
