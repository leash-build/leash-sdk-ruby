# frozen_string_literal: true

require_relative "lib/leash"

Gem::Specification.new do |spec|
  spec.name          = "leash-sdk"
  spec.version       = Leash::VERSION
  spec.authors       = ["Leash"]
  spec.email         = ["hello@leash.build"]

  spec.summary       = "Ruby SDK for the Leash platform integrations API"
  spec.description   = "Access Gmail, Google Calendar, Google Drive, and more through the Leash platform proxy. No API keys needed -- uses your Leash auth token."
  spec.homepage      = "https://github.com/leash-build/leash-sdk-ruby"
  spec.license       = "Apache-2.0"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*.rb"] + ["leash-sdk.gemspec", "Gemfile", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # No runtime dependencies -- stdlib only (net/http, json, uri).
end
