# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

# --------------------------------------------------------------------------
# Static checks: verify no web-framework requires in source files.
# Runtime isolation: verify the gem loads in a clean subprocess.
# --------------------------------------------------------------------------

class TestStaticDependencies < Minitest::Test
  LIB_DIR = File.expand_path("../../lib", __FILE__)

  # Web framework gems that must never appear in a require/require_relative.
  FORBIDDEN_GEMS = %w[rails sinatra rack grape hanami roda].freeze

  # Allowed stdlib requires (the ones the SDK actually uses).
  ALLOWED_REQUIRES = %w[net/http json uri cgi jwt base64].freeze

  def self.lib_ruby_files
    Dir.glob(File.join(LIB_DIR, "**", "*.rb"))
  end

  # Generate one test per source file so failures pinpoint the exact file.
  lib_ruby_files.each do |filepath|
    relative = filepath.sub("#{LIB_DIR}/", "")
    method_name = "test_no_forbidden_requires_in_#{relative.gsub(/[\/.]/, '_')}"

    define_method(method_name) do
      lines = File.readlines(filepath)
      lines.each_with_index do |line, idx|
        # Skip comments
        stripped = line.lstrip
        next if stripped.start_with?("#")

        # Match require statements (require "x" or require 'x')
        if stripped.match?(/\brequire\s+['"]/)
          FORBIDDEN_GEMS.each do |gem|
            refute stripped.match?(/\brequire\s+['"]#{gem}['"\/]/),
              "#{relative}:#{idx + 1} requires forbidden gem '#{gem}': #{line.strip}"
          end
        end
      end
    end
  end

  def test_source_files_exist
    files = self.class.lib_ruby_files
    assert files.length >= 6, "Expected at least 6 .rb files in lib/, found #{files.length}"
  end

  def test_only_stdlib_requires
    all_requires = []
    self.class.lib_ruby_files.each do |filepath|
      File.readlines(filepath).each_with_index do |line, idx|
        stripped = line.lstrip
        next if stripped.start_with?("#")

        if (m = stripped.match(/\brequire\s+['"]([^'"]+)['"]/))
          all_requires << { file: filepath, line: idx + 1, gem: m[1] }
        end
      end
    end

    all_requires.each do |entry|
      gem_name = entry[:gem]
      # Allow stdlib requires and require_relative (which won't match this pattern
      # since require_relative uses a different keyword)
      is_stdlib = ALLOWED_REQUIRES.any? { |allowed| gem_name == allowed || gem_name.start_with?("#{allowed}/") }
      assert is_stdlib,
        "#{entry[:file]}:#{entry[:line]} requires '#{gem_name}' which is not in the allowed stdlib list: #{ALLOWED_REQUIRES.join(', ')}"
    end
  end
end

class TestRuntimeIsolation < Minitest::Test
  LIB_DIR = File.expand_path("../../lib", __FILE__)

  def test_require_leash_in_clean_subprocess
    # Build a Ruby command that loads only the SDK's lib/ directory,
    # requires leash, and verifies key classes are defined.
    ruby_code = <<~'RUBY'
      require "leash"
      raise "Leash::Integrations not defined" unless defined?(Leash::Integrations)
      raise "Leash::GmailClient not defined" unless defined?(Leash::GmailClient)
      raise "Leash::CalendarClient not defined" unless defined?(Leash::CalendarClient)
      raise "Leash::DriveClient not defined" unless defined?(Leash::DriveClient)
      raise "Leash::Error not defined" unless defined?(Leash::Error)
      puts "OK"
    RUBY

    # Use -I to add only the SDK lib dir. Clear RUBYLIB to avoid picking up
    # anything extra. We keep the default Ruby stdlib on the load path.
    env = { "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil }
    out, status = Open3.capture2(env, RbConfig.ruby, "-I", LIB_DIR, "-e", ruby_code)

    assert status.success?,
      "Subprocess failed (exit #{status.exitstatus}). The SDK could not be required in a clean environment without web frameworks."
    assert_equal "OK", out.strip,
      "Expected subprocess to print OK, got: #{out.strip}"
  end

  def test_no_web_frameworks_loaded_in_subprocess
    # Require leash, then check $LOADED_FEATURES for any web framework files.
    ruby_code = <<~'RUBY'
      require "leash"
      frameworks = %w[rails sinatra rack grape hanami roda]
      loaded = $LOADED_FEATURES.select { |f| frameworks.any? { |fw| f.include?(fw) } }
      if loaded.empty?
        puts "CLEAN"
      else
        puts "DIRTY: #{loaded.join(', ')}"
      end
    RUBY

    env = { "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil }
    out, status = Open3.capture2(env, RbConfig.ruby, "-I", LIB_DIR, "-e", ruby_code)

    assert status.success?, "Subprocess failed (exit #{status.exitstatus})"
    assert_equal "CLEAN", out.strip,
      "Web framework files were loaded: #{out.strip}"
  end
end
