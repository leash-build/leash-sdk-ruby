# frozen_string_literal: true

require_relative "test_helper"

class TestAuthFacade < Minitest::Test
  def setup
    @orig_secret = ENV.delete("LEASH_JWT_SECRET")
  end

  def teardown
    ENV["LEASH_JWT_SECRET"] = @orig_secret if @orig_secret
  end

  def test_user_returns_user_when_cookie_valid
    token = make_token
    client = Leash.new(request: rack_env(cookie: token))
    user = client.auth.user
    assert_instance_of Leash::User, user
    assert_equal "user-123", user.id
    assert_equal "alice@example.com", user.email
  end

  def test_user_returns_nil_when_no_cookie
    client = Leash.new(request: rack_env)
    assert_nil client.auth.user
  end

  def test_user_returns_nil_when_token_invalid
    client = Leash.new(request: rack_env(cookie: "not-a-jwt"))
    assert_nil client.auth.user
  end

  def test_user_returns_nil_when_token_expired
    ENV["LEASH_JWT_SECRET"] = "secret"
    expired = make_token(secret: "secret", exp: Time.now.to_i - 60)
    client = Leash.new(request: rack_env(cookie: expired))
    assert_nil client.auth.user
  end

  def test_authenticated_predicate_true
    client = Leash.new(request: rack_env(cookie: make_token))
    assert client.auth.authenticated?
  end

  def test_authenticated_predicate_false
    client = Leash.new(request: rack_env)
    refute client.auth.authenticated?
  end

  # Legacy Leash::Auth.get_user still works for callers on the 0.3 surface.
  def test_legacy_get_user_still_raises_for_missing_cookie
    err = assert_raises(Leash::AuthError) { Leash::Auth.get_user({}) }
    assert_includes err.message, "Missing leash-auth cookie"
  end

  def test_legacy_authenticated_predicate
    request = { "HTTP_COOKIE" => "leash-auth=#{make_token}" }
    assert Leash::Auth.authenticated?(request)
  end
end

class TestAuthExtraction < Minitest::Test
  def test_extract_cookie_from_rack_hash
    request = { "HTTP_COOKIE" => "leash-auth=abc; other=xyz" }
    assert_equal "abc", Leash::Auth.extract_cookie(request)
  end

  def test_extract_cookie_from_cookies_jar
    request_class = Struct.new(:cookies)
    request = request_class.new({ "leash-auth" => "jar-value" })
    assert_equal "jar-value", Leash::Auth.extract_cookie(request)
  end

  def test_extract_cookie_from_cookies_jar_with_morsel_like_value
    morsel = Struct.new(:value).new("morsel-value")
    request = Struct.new(:cookies).new({ "leash-auth" => morsel })
    assert_equal "morsel-value", Leash::Auth.extract_cookie(request)
  end

  def test_extract_cookie_returns_nil_for_unknown_shape
    assert_nil Leash::Auth.extract_cookie(Object.new)
    assert_nil Leash::Auth.extract_cookie(nil)
  end

  def test_extract_bearer_token_from_rack_env
    request = { "HTTP_AUTHORIZATION" => "Bearer some-jwt" }
    assert_equal "some-jwt", Leash::Auth.extract_bearer_token(request)
  end

  def test_extract_bearer_token_case_insensitive_scheme
    request = { "HTTP_AUTHORIZATION" => "bearer my-jwt" }
    assert_equal "my-jwt", Leash::Auth.extract_bearer_token(request)
  end

  def test_extract_bearer_token_returns_nil_on_basic_auth
    request = { "HTTP_AUTHORIZATION" => "Basic dXNlcjpwYXNz" }
    assert_nil Leash::Auth.extract_bearer_token(request)
  end

  def test_extract_bearer_token_returns_nil_when_missing
    assert_nil Leash::Auth.extract_bearer_token({})
    assert_nil Leash::Auth.extract_bearer_token(nil)
  end

  def test_extract_bearer_token_strips_whitespace
    request = { "HTTP_AUTHORIZATION" => "Bearer   spaced-jwt   " }
    assert_equal "spaced-jwt", Leash::Auth.extract_bearer_token(request)
  end

  def test_extract_bearer_token_from_object_with_headers
    request_class = Struct.new(:headers)
    request = request_class.new({ "Authorization" => "Bearer obj-jwt" })
    assert_equal "obj-jwt", Leash::Auth.extract_bearer_token(request)
  end
end
