# frozen_string_literal: true

module Leash
  module Integrations
    # @api private
    # Internal base class — wraps a {Leash::Transport} bound to a provider id.
    class Base
      PROVIDER = nil

      def initialize(transport)
        @transport = transport
      end

      private

      def call(action, params = nil)
        @transport.call(self.class::PROVIDER, action, params)
      end

      # Drop nil values from a hash so we never send `{"foo":null}` payloads
      # — mirrors the Python provider behaviour.
      def compact_params(hash)
        result = {}
        hash.each { |k, v| result[k] = v unless v.nil? }
        result
      end
    end

    # Generic escape hatch — call any provider action without a typed wrapper.
    # Returned by `leash.integrations.provider(name)`.
    class Caller
      def initialize(transport, name)
        @transport = transport
        @name = name
      end

      # Invoke `<provider>/<action>` with an optional JSON body.
      #
      # @param action [String] the wire action (e.g. `'post_message'`)
      # @param body [Hash, nil] JSON body forwarded to the platform
      def call(action, body: nil)
        @transport.call(@name, action, body)
      end

      attr_reader :name
    end
  end
end
