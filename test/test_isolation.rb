# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

# Static + runtime isolation: the SDK must not require any web framework gem.

class TestStaticDependencies < Minitest::Test
  LIB_DIR = File.expand_path("../../lib", __FILE__)
  FORBIDDEN_GEMS = %w[rails sinatra rack grape hanami roda].freeze
  ALLOWED_REQUIRES = %w[net/http json uri cgi jwt base64].freeze

  def self.lib_ruby_files
    Dir.glob(File.join(LIB_DIR, "**", "*.rb"))
  end

  lib_ruby_files.each do |filepath|
    relative = filepath.sub("#{LIB_DIR}/", "")
    method_name = "test_no_forbidden_requires_in_#{relative.gsub(%r{[/.]}, '_')}"

    define_method(method_name) do
      File.readlines(filepath).each_with_index do |line, idx|
        stripped = line.lstrip
        next if stripped.start_with?("#")
        next unless stripped.match?(/\brequire\s+['"]/)

        FORBIDDEN_GEMS.each do |gem|
          refute stripped.match?(/\brequire\s+['"]#{gem}['"\/]/),
                  "#{relative}:#{idx + 1} requires forbidden gem '#{gem}': #{line.strip}"
        end
      end
    end
  end

  def test_source_files_exist
    files = self.class.lib_ruby_files
    assert files.length >= 8, "Expected at least 8 .rb files in lib/, found #{files.length}"
  end

  def test_only_stdlib_requires
    self.class.lib_ruby_files.each do |filepath|
      File.readlines(filepath).each_with_index do |line, idx|
        stripped = line.lstrip
        next if stripped.start_with?("#")
        m = stripped.match(/\brequire\s+['"]([^'"]+)['"]/)
        next unless m

        gem_name = m[1]
        ok = ALLOWED_REQUIRES.any? { |a| gem_name == a || gem_name.start_with?("#{a}/") }
        assert ok, "#{filepath}:#{idx + 1} requires '#{gem_name}' (not in allowlist #{ALLOWED_REQUIRES.join(', ')})"
      end
    end
  end
end

class TestRuntimeIsolation < Minitest::Test
  LIB_DIR = File.expand_path("../../lib", __FILE__)

  def test_require_leash_in_clean_subprocess
    ruby_code = <<~'RUBY'
      require "leash"
      raise "Leash module missing" unless defined?(Leash)
      raise "Leash::Client missing" unless defined?(Leash::Client)
      raise "Leash::Error missing"  unless defined?(Leash::Error)
      raise "Integrations::Gmail missing" unless defined?(Leash::Integrations::Gmail)
      raise "Integrations::Calendar missing" unless defined?(Leash::Integrations::Calendar)
      raise "Integrations::Drive missing" unless defined?(Leash::Integrations::Drive)
      raise "Integrations::Linear missing" unless defined?(Leash::Integrations::Linear)
      raise "Env missing" unless defined?(Leash::Env)
      raise "Transport missing" unless defined?(Leash::Transport)
      puts "OK"
    RUBY

    env = { "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil }
    out, status = Open3.capture2(env, RbConfig.ruby, "-I", LIB_DIR, "-e", ruby_code)
    assert status.success?, "Subprocess exit #{status.exitstatus}: #{out}"
    assert_equal "OK", out.strip
  end

  def test_no_web_frameworks_loaded
    ruby_code = <<~'RUBY'
      require "leash"
      frameworks = %w[rails sinatra rack grape hanami roda]
      loaded = $LOADED_FEATURES.select { |f| frameworks.any? { |fw| f.include?(fw) } }
      puts loaded.empty? ? "CLEAN" : "DIRTY: #{loaded.join(',')}"
    RUBY

    env = { "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil }
    out, status = Open3.capture2(env, RbConfig.ruby, "-I", LIB_DIR, "-e", ruby_code)
    assert status.success?
    assert_equal "CLEAN", out.strip
  end
end
