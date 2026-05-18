# frozen_string_literal: true

require_relative "test_helper"

class TestEnv < Minitest::Test
  def make_env(canned)
    runner = RecordingRunner.new(canned)
    transport = Leash::Transport.new(
      platform_url: "https://leash.test",
      api_key: "lsk_live_test",
      http_runner: runner
    )
    env = Leash::Env.new(platform_url: "https://leash.test", api_key: "lsk_live_test", transport: transport)
    [env, runner]
  end

  def test_get_returns_value
    env, _ = make_env(FakeResponse.new(200, '{"value":"super-secret"}'))
    assert_equal "super-secret", env.get("DB_URL")
  end

  def test_get_caches_value
    env, runner = make_env(FakeResponse.new(200, '{"value":"v"}'))
    env.get("FOO")
    env.get("FOO")
    env.get("FOO")
    assert_equal 1, runner.call_count
  end

  def test_get_fresh_bypasses_cache
    env, runner = make_env(FakeResponse.new(200, '{"value":"v"}'))
    env.get("FOO")
    env.get("FOO", fresh: true)
    assert_equal 2, runner.call_count
  end

  def test_get_returns_nil_on_404
    env, _ = make_env(FakeResponse.new(404, '{"error":"not declared"}'))
    assert_nil env.get("NOPE")
  end

  def test_get_caches_nil_too
    env, runner = make_env(FakeResponse.new(404, ""))
    env.get("MISSING")
    env.get("MISSING")
    assert_equal 1, runner.call_count
  end

  def test_get_raises_on_401
    env, _ = make_env(FakeResponse.new(401, '{"error":"unauth"}'))
    err = assert_raises(Leash::UnauthorizedError) { env.get("X") }
    assert_equal "UNAUTHORIZED", err.code
  end

  def test_get_raises_on_400_with_invalid_key_code
    env, _ = make_env(FakeResponse.new(400, '{"error":"invalid"}'))
    err = assert_raises(Leash::Error) { env.get("bad name") }
    assert_equal "INVALID_KEY", err.code
  end

  def test_get_raises_on_402_with_upgrade_required
    env, _ = make_env(FakeResponse.new(402, '{"requiredPlan":"growth"}'))
    err = assert_raises(Leash::UpgradeRequiredError) { env.get("X") }
    assert_equal "UPGRADE_REQUIRED", err.code
    assert_includes err.message, "growth"
  end

  def test_get_raises_on_502_with_source_resync_failed
    env, _ = make_env(FakeResponse.new(502, '{"error":"vault down"}'))
    err = assert_raises(Leash::Error) { env.get("X") }
    assert_equal "SOURCE_RESYNC_FAILED", err.code
  end

  def test_get_raises_when_no_api_key
    runner = RecordingRunner.new(FakeResponse.new(200, '{}'))
    transport = Leash::Transport.new(platform_url: "https://x", api_key: nil, http_runner: runner)
    env = Leash::Env.new(platform_url: "https://x", api_key: nil, transport: transport)
    err = assert_raises(Leash::Error) { env.get("X") }
    assert_equal "NO_API_KEY", err.code
  end

  def test_get_url_includes_key_encoded
    env, runner = make_env(FakeResponse.new(200, '{"value":"v"}'))
    env.get("MY KEY/SPECIAL")
    assert_equal "/api/apps/me/secrets/MY%20KEY%2FSPECIAL", runner.uri.path
  end

  def test_get_sends_bearer_auth
    env, runner = make_env(FakeResponse.new(200, '{"value":"v"}'))
    env.get("X")
    assert_equal "Bearer lsk_live_test", runner.request_headers["Authorization"]
  end

  def test_get_many_returns_hash
    env, _ = make_env(FakeResponse.new(200, '{"value":"shared"}'))
    result = env.get_many(["A", "B"])
    assert_equal({ "A" => "shared", "B" => "shared" }, result)
  end

  def test_get_many_mixes_nil_and_value
    # First call returns value, second returns 404. Tricky to script with a
    # single canned response — substitute mid-test.
    runner = RecordingRunner.new(FakeResponse.new(200, '{"value":"a-value"}'))
    transport = Leash::Transport.new(platform_url: "https://x", api_key: "k", http_runner: runner)
    env = Leash::Env.new(platform_url: "https://x", api_key: "k", transport: transport)
    env.get("A")
    runner.canned = FakeResponse.new(404, "")
    assert_nil env.get("B")
    assert_equal "a-value", env.get("A")  # cache hit, no 5th call
  end

  def test_unknown_status_raises_env_fetch_error
    env, _ = make_env(FakeResponse.new(503, ""))
    err = assert_raises(Leash::Error) { env.get("X") }
    assert_equal "ENV_FETCH_ERROR", err.code
  end

  def test_malformed_body_raises_env_fetch_error
    env, _ = make_env(FakeResponse.new(200, '{"not-value":"hmm"}'))
    err = assert_raises(Leash::Error) { env.get("X") }
    assert_equal "ENV_FETCH_ERROR", err.code
  end
end
