# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "jwt"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "leash"

# --------------------------------------------------------------------------
# Shared helpers
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

# A fake "response" object that quacks like Net::HTTPResponse — `.code`
# returns a String like "200" and `.body` returns the raw body.
FakeResponse = Struct.new(:code, :body) do
  def initialize(code, body)
    code_str = code.is_a?(Integer) ? code.to_s : code
    super(code_str, body)
  end
end

# Captures the last URI + Net::HTTP request made. Pluggable into
# `Leash::Transport.new(http_runner: ...)`.
class RecordingRunner
  attr_reader :uri, :request, :call_count
  attr_accessor :canned

  def initialize(canned = FakeResponse.new(200, '{"success":true,"data":{}}'))
    @canned = canned
    @call_count = 0
  end

  def to_proc
    proc { |uri, request| record_and_respond(uri, request) }
  end

  def record_and_respond(uri, request)
    @uri = uri
    @request = request
    @call_count += 1
    @canned
  end

  def call(uri, request)
    record_and_respond(uri, request)
  end

  def request_body
    JSON.parse(@request.body) if @request.respond_to?(:body) && @request.body && !@request.body.empty?
  end

  def request_headers
    return CaseInsensitiveHeaders.new unless @request

    headers = CaseInsensitiveHeaders.new
    @request.each_header { |k, v| headers[k] = v }
    headers
  end
end

# Net::HTTP returns request headers with their canonical casing, but newer
# Ruby/Net::HTTP releases store them lower-case via `each_header`. Tests
# assert on either casing so we use a CI hash that ignores case on lookup.
class CaseInsensitiveHeaders
  def initialize
    @store = {}
  end

  def []=(key, value)
    @store[key.to_s.downcase] = value
  end

  def [](key)
    @store[key.to_s.downcase]
  end

  def key?(key)
    @store.key?(key.to_s.downcase)
  end

  def to_h
    @store.dup
  end

  def inspect
    @store.inspect
  end
end

# Build a Leash client wired to a recording transport.
def build_client(canned: FakeResponse.new(200, '{"success":true,"data":{}}'),
                 request: { "HTTP_COOKIE" => "leash-auth=cookie-jwt" },
                 api_key: "lsk_live_test",
                 platform_url: "https://leash.test")
  runner = RecordingRunner.new(canned)
  transport = Leash::Transport.new(
    platform_url: platform_url,
    api_key: api_key,
    cookie_value: Leash::Auth.extract_cookie(request),
    http_runner: runner
  )
  client = Leash::Client.new(
    request: request,
    platform_url: platform_url,
    api_key: api_key,
    transport: transport
  )
  [client, runner]
end

# Convenience for tests that just want a request-shaped Hash.
def rack_env(cookie: nil, auth: nil)
  env = {}
  env["HTTP_COOKIE"] = "leash-auth=#{cookie}" if cookie
  env["HTTP_AUTHORIZATION"] = "Bearer #{auth}" if auth
  env
end
