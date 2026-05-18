# frozen_string_literal: true

require_relative "lib/leash/version"

Gem::Specification.new do |spec|
  spec.name          = "leash-sdk"
  spec.version       = Leash::VERSION
  spec.authors       = ["Leash"]
  spec.email         = ["hello@leash.build"]

  spec.summary       = "Unified Ruby SDK for the Leash platform — auth, env, integrations."
  spec.description   = "Server-side Leash client. Resolve the request user, read app env-vars at runtime, and call platform integrations (Gmail, Google Calendar, Google Drive, Linear, plus a generic escape hatch). Framework-agnostic — works with Rails, Sinatra, Hanami, or plain Rack."
  spec.homepage      = "https://github.com/leash-build/leash-sdk-ruby"
  spec.license       = "Apache-2.0"
  spec.required_ruby_version = ">= 2.7"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*.rb"] + ["leash-sdk.gemspec", "Gemfile", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "jwt", ">= 2.7"

  spec.add_development_dependency "minitest", ">= 5.0"
end
