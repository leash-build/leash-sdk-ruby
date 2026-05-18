# frozen_string_literal: true

require_relative "test_helper"

class TestErrors < Minitest::Test
  def test_error_carries_all_fields
    err = Leash::Error.new("nope",
                            code: "X", action: "do y", see_also: "https://z",
                            status: 418, cause: StandardError.new("inner"))
    assert_equal "nope", err.message
    assert_equal "X", err.code
    assert_equal "do y", err.action
    assert_equal "https://z", err.see_also
    assert_equal 418, err.status
    assert_kind_of StandardError, err.cause
  end

  def test_error_to_s_includes_action_and_see_also
    err = Leash::Error.new("oops", action: "fix", see_also: "https://x")
    s = err.to_s
    assert_includes s, "oops"
    assert_includes s, "Fix: fix"
    assert_includes s, "See: https://x"
  end

  def test_subclass_codes
    assert_equal "UPGRADE_REQUIRED", Leash::UpgradeRequiredError.new.code
    assert_equal "INTEGRATION_NOT_ENABLED", Leash::ConnectionRequiredError.new.code
    assert_equal "KEY_NOT_DECLARED", Leash::KeyNotDeclaredError.new.code
    assert_equal "UNAUTHORIZED", Leash::UnauthorizedError.new.code
    assert_equal "NETWORK_ERROR", Leash::NetworkError.new.code
  end

  def test_plan_block_error_alias
    assert_same Leash::UpgradeRequiredError, Leash::PlanBlockError
  end

  def test_not_connected_error_alias
    assert_same Leash::ConnectionRequiredError, Leash::NotConnectedError
  end

  def test_hierarchy
    assert Leash::UpgradeRequiredError < Leash::Error
    assert Leash::ConnectionRequiredError < Leash::Error
    assert Leash::KeyNotDeclaredError < Leash::Error
    assert Leash::UnauthorizedError < Leash::Error
    assert Leash::NetworkError < Leash::Error
    assert Leash::AuthError < Leash::Error
    assert Leash::Error < StandardError
  end

  def test_token_expired_error_kept_for_backcompat
    err = Leash::TokenExpiredError.new
    assert_equal "token_expired", err.code
    assert err.is_a?(Leash::Error)
  end

  def test_connect_url_accessible
    err = Leash::Error.new("x", connect_url: "https://connect")
    assert_equal "https://connect", err.connect_url
  end
end

class TestUser < Minitest::Test
  def test_user_equality
    a = Leash::User.new(id: "1", email: "x@y", name: "X", picture: "p")
    b = Leash::User.new(id: "1", email: "x@y", name: "X", picture: "p")
    assert_equal a, b
  end

  def test_user_inequality
    a = Leash::User.new(id: "1", email: "x@y")
    b = Leash::User.new(id: "2", email: "x@y")
    refute_equal a, b
  end

  def test_leash_user_alias
    assert_same Leash::User, Leash::LeashUser
  end
end
