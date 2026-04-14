# frozen_string_literal: true

module Leash
  # Untyped client for a custom integration.
  #
  # Obtained via {Integrations#integration}. Proxies requests through the
  # Leash platform at +/api/integrations/custom/{name}+.
  #
  # @example
  #   stripe = client.integration("stripe")
  #   charges = stripe.call("/v1/charges", method: "GET")
  class CustomIntegration
    # @param name [String] the custom integration name
    # @param call_fn [Method] internal callable that performs the HTTP request
    def initialize(name, call_fn)
      @name = name
      @call_fn = call_fn
    end

    # Invoke the custom integration proxy.
    #
    # @param path [String] the endpoint path to forward (e.g. "/users")
    # @param method [String] HTTP method (default "GET")
    # @param body [Hash, nil] optional JSON body to forward
    # @param headers [Hash, nil] optional extra headers to forward
    # @return [Object] the "data" field from the platform response
    # @raise [Leash::Error] if the platform returns a non-success response
    def call(path, method: "GET", body: nil, headers: nil)
      @call_fn.call(@name, path, method, body, headers)
    end
  end
end
