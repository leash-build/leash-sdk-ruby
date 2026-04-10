# frozen_string_literal: true

module Leash
  # Base error class for all Leash SDK errors.
  #
  # @attr_reader [String, nil] code the error code from the platform
  # @attr_reader [String, nil] connect_url the OAuth connect URL (present when provider is not connected)
  class Error < StandardError
    attr_reader :code, :connect_url

    # @param message [String] human-readable error message
    # @param code [String, nil] machine-readable error code
    # @param connect_url [String, nil] URL to initiate OAuth connection
    def initialize(message, code: nil, connect_url: nil)
      super(message)
      @code = code
      @connect_url = connect_url
    end
  end

  # Raised when the provider is not connected for the current user.
  class NotConnectedError < Error
    def initialize(message = "Integration not connected", connect_url: nil)
      super(message, code: "not_connected", connect_url: connect_url)
    end
  end

  # Raised when the OAuth token has expired and needs to be refreshed.
  class TokenExpiredError < Error
    def initialize(message = "Token expired", connect_url: nil)
      super(message, code: "token_expired", connect_url: connect_url)
    end
  end
end
