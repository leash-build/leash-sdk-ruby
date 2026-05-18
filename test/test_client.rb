# frozen_string_literal: true

require_relative "test_helper"

# Constructor / namespace wiring tests.
class TestClientConstruction < Minitest::Test
  def test_requires_request_keyword
    err = assert_raises(Leash::Error) { Leash.new(request: nil) }
    assert_equal "NO_REQUEST_SERVER_CONSTRUCT", err.code
  end

  def test_accepts_rack_hash
    client = Leash.new(request: rack_env(cookie: "abc"))
    assert_equal "abc", client.cookie_value
  end

  def test_accepts_object_with_cookies_method
    request_class = Struct.new(:cookies)
    request = request_class.new({ "leash-auth" => "from-jar" })
    client = Leash.new(request: request)
    assert_equal "from-jar", client.cookie_value
  end

  def test_accepts_object_with_env_hash
    request_class = Struct.new(:env)
    request = request_class.new({ "HTTP_COOKIE" => "leash-auth=from-env" })
    client = Leash.new(request: request)
    assert_equal "from-env", client.cookie_value
  end

  def test_accepts_get_header_fallback
    request_class = Class.new do
      def get_header(name)
        return "leash-auth=via-get-header" if name == "HTTP_COOKIE"
      end
    end
    client = Leash.new(request: request_class.new)
    assert_equal "via-get-header", client.cookie_value
  end

  def test_platform_url_from_arg
    client = Leash.new(request: rack_env(cookie: "x"), platform_url: "https://custom.example.com/")
    assert_equal "https://custom.example.com", client.platform_url
  end

  def test_platform_url_from_env
    original = ENV["LEASH_PLATFORM_URL"]
    ENV["LEASH_PLATFORM_URL"] = "https://staging.leash.build/"
    client = Leash.new(request: rack_env(cookie: "x"))
    assert_equal "https://staging.leash.build", client.platform_url
  ensure
    if original
      ENV["LEASH_PLATFORM_URL"] = original
    else
      ENV.delete("LEASH_PLATFORM_URL")
    end
  end

  def test_platform_url_defaults_to_leash_build
    original = ENV.delete("LEASH_PLATFORM_URL")
    client = Leash.new(request: rack_env(cookie: "x"))
    assert_equal Leash::DEFAULT_PLATFORM_URL, client.platform_url
  ensure
    ENV["LEASH_PLATFORM_URL"] = original if original
  end

  def test_returns_namespaces
    client = Leash.new(request: rack_env(cookie: "x"))
    assert_kind_of Leash::Client::AuthFacade, client.auth
    assert_kind_of Leash::Env, client.env
    assert_kind_of Leash::Integrations::Namespace, client.integrations
  end

  def test_integration_namespaces_are_typed
    client = Leash.new(request: rack_env(cookie: "x"))
    assert_instance_of Leash::Integrations::Gmail, client.integrations.gmail
    assert_instance_of Leash::Integrations::Calendar, client.integrations.calendar
    assert_instance_of Leash::Integrations::Drive, client.integrations.drive
    assert_instance_of Leash::Integrations::Linear, client.integrations.linear
  end

  def test_google_aliases_point_to_same_instances
    client = Leash.new(request: rack_env(cookie: "x"))
    assert_same client.integrations.calendar, client.integrations.google_calendar
    assert_same client.integrations.drive, client.integrations.google_drive
  end

  def test_provider_returns_caller
    client = Leash.new(request: rack_env(cookie: "x"))
    slack = client.integrations.provider("slack")
    assert_instance_of Leash::Integrations::Caller, slack
    assert_equal "slack", slack.name
  end
end

# Auth precedence tests — Critical #2 in the 0.4 plan.
class TestAuthPrecedence < Minitest::Test
  def setup
    @orig_key = ENV.delete("LEASH_API_KEY")
  end

  def teardown
    if @orig_key
      ENV["LEASH_API_KEY"] = @orig_key
    else
      ENV.delete("LEASH_API_KEY")
    end
  end

  def test_explicit_api_key_wins_over_env
    ENV["LEASH_API_KEY"] = "from-env"
    client = Leash.new(request: rack_env, api_key: "explicit")
    assert_equal "explicit", client.explicit_api_key
  end

  def test_env_api_key_wins_over_bearer
    ENV["LEASH_API_KEY"] = "from-env"
    client = Leash.new(request: rack_env(auth: "user-jwt"))
    assert_equal "from-env", client.explicit_api_key
  end

  def test_bearer_used_for_env_fallback_when_no_api_key
    # No LEASH_API_KEY → bearer token is used as the env-read credential.
    client = Leash.new(request: rack_env(auth: "user-jwt"))
    assert_nil client.explicit_api_key
    assert_equal "user-jwt", client.bearer_token
  end

  def test_bearer_extracted_when_present
    client = Leash.new(request: rack_env(auth: "abc.def.ghi"))
    assert_equal "abc.def.ghi", client.bearer_token
  end

  def test_cookie_extracted_when_present
    client = Leash.new(request: rack_env(cookie: "jwt-from-cookie"))
    assert_equal "jwt-from-cookie", client.cookie_value
  end

  def test_all_three_can_coexist
    ENV["LEASH_API_KEY"] = "lsk_live_key"
    client = Leash.new(
      request: rack_env(cookie: "cookie-jwt", auth: "bearer-jwt"),
      api_key: "lsk_live_key"
    )
    assert_equal "lsk_live_key", client.explicit_api_key
    assert_equal "bearer-jwt", client.bearer_token
    assert_equal "cookie-jwt", client.cookie_value
  end
end
