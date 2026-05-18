# frozen_string_literal: true

module Leash
  # Structured error type raised by every Leash SDK call site.
  #
  # Mirrors `leash-sdk-ts/src/errors.ts` and Python's `leash.errors.LeashError`.
  # The `code` field is the stable machine-readable identifier consumers should
  # switch on; `message` is the human-readable line; `action` and `see_also`
  # are optional remediation hints.
  #
  # Known codes (kept in sync with leash-sdk-ts):
  #   - NO_API_KEY
  #   - NO_REQUEST_SERVER_CONSTRUCT
  #   - BROWSER_MODE_UNSUPPORTED
  #   - UNAUTHORIZED
  #   - NO_AUTH_CONTEXT
  #   - INTEGRATION_NOT_ENABLED
  #   - INTEGRATION_ERROR
  #   - UPGRADE_REQUIRED
  #   - PLAN_BLOCK
  #   - CONNECTION_REQUIRED
  #   - NETWORK_ERROR
  #   - KEY_NOT_DECLARED
  #   - INVALID_KEY
  #   - SOURCE_RESYNC_FAILED
  #   - ENV_FETCH_ERROR
  class Error < StandardError
    attr_reader :code, :action, :see_also, :status, :cause

    def initialize(message, code: nil, action: nil, see_also: nil, status: nil,
                   cause: nil, connect_url: nil)
      super(message)
      @message = message
      @code = code
      @action = action
      @see_also = see_also
      @status = status
      @cause = cause
      @connect_url = connect_url
    end

    # Compatibility shim — the 0.3 surface exposed `connect_url`.
    def connect_url
      @connect_url
    end

    # Override `message` to return our stored value — avoids Exception#message
    # falling back to `to_s` and recursing infinitely.
    def message
      @message
    end

    def to_s
      out = +"x #{@message}"
      out << "\n  Fix: #{@action}" if @action
      out << "\n  See: #{@see_also}" if @see_also
      out
    end
  end

  # 402 from the platform — feature requires a higher plan.
  class UpgradeRequiredError < Error
    def initialize(message = "This feature requires a higher plan.", **opts)
      opts[:code] ||= "UPGRADE_REQUIRED"
      super(message, **opts)
    end
  end

  # Alias kept for the surface contract described in the 0.4 plan
  # (`Leash::PlanBlockError`). Same class as `UpgradeRequiredError`.
  PlanBlockError = UpgradeRequiredError

  # 403 from the platform — provider not connected for the current user.
  class ConnectionRequiredError < Error
    def initialize(message = "Integration not connected.", **opts)
      opts[:code] ||= "INTEGRATION_NOT_ENABLED"
      super(message, **opts)
    end
  end

  # 404 on env.get — env-var key isn't declared / not found.
  class KeyNotDeclaredError < Error
    def initialize(message = "Key is not declared.", **opts)
      opts[:code] ||= "KEY_NOT_DECLARED"
      super(message, **opts)
    end
  end

  # 401 from the platform — missing / invalid credentials.
  class UnauthorizedError < Error
    def initialize(message = "Unauthorized.", **opts)
      opts[:code] ||= "UNAUTHORIZED"
      super(message, **opts)
    end
  end

  # Transport-level failure (DNS, refused connection, timeout, …).
  class NetworkError < Error
    def initialize(message = "Failed to reach the Leash platform.", **opts)
      opts[:code] ||= "NETWORK_ERROR"
      super(message, **opts)
    end
  end

  # Backwards-compat alias for the 0.3 surface — kept so existing user code
  # `rescue Leash::NotConnectedError` keeps working.
  NotConnectedError = ConnectionRequiredError

  class TokenExpiredError < Error
    def initialize(message = "Token expired.", **opts)
      # Legacy code casing — kept as snake_case to preserve 0.3 behavior for
      # callers matching on err.code. New errors use SCREAMING_SNAKE.
      opts[:code] ||= "token_expired"
      super(message, **opts)
    end
  end

  # Raised by `Leash::Auth.get_user` when the leash-auth cookie is missing /
  # invalid. `Leash#auth.user` returns `nil` instead so it never raises.
  class AuthError < Error
    def initialize(message = "Authentication failed", **opts)
      opts[:code] ||= "NO_AUTH_CONTEXT"
      super(message, **opts)
    end
  end
end
