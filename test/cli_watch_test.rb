# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "rbconfig"
require "stringio"
require "timeout"
require "tmpdir"

# Stateful hooks keep source mutation and the observed watch iteration together.
# rubocop:disable Metrics/BlockLength, Metrics/MethodLength
class CLIWatchTest < Minitest::Test
  def test_rebuilds_after_a_stable_source_change_without_real_sleep
    Dir.mktmpdir("ibex-watch") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      manifest = File.join(directory, "parser.ibex.json")
      File.binwrite(grammar, grammar_source("P"))
      initial_digest = nil
      sleeps = 0
      hook = lambda do |event, iteration, _paths|
        raise "watch did not converge" if iteration > 8
        next unless event == :after_build && File.exist?(manifest)

        digest = manifest_input_digest(manifest)
        if initial_digest
          :stop if digest != initial_digest
        else
          initial_digest = digest
          File.binwrite(grammar, grammar_source("Changed"))
          nil
        end
      end

      status = run_watch(
        ["--manifest", "-o", parser, grammar],
        hook: hook,
        sleeper: ->(_seconds) { sleeps += 1 }
      )

      assert_equal 0, status
      assert_operator sleeps, :>, 0
      refute_equal initial_digest, manifest_input_digest(manifest)
      assert Ibex::GenerationManifest.validate_file(manifest)
    end
  end

  def test_failed_build_is_reported_once_and_keeps_last_success_until_recovery
    Dir.mktmpdir("ibex-watch") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      manifest = File.join(directory, "parser.ibex.json")
      File.binwrite(grammar, grammar_source("P"))
      successful_manifest = nil
      failure_observed = false
      errors = StringIO.new
      hook = lambda do |event, iteration, _paths|
        raise "watch did not converge" if iteration > 10
        next unless event == :after_build

        if File.exist?(manifest) && successful_manifest.nil?
          successful_manifest = File.binread(manifest)
          File.binwrite(grammar, "not a grammar\n")
          nil
        elsif errors.string.include?("expected class") && !failure_observed
          failure_observed = true
          assert_equal successful_manifest, File.binread(manifest)
          File.binwrite(grammar, grammar_source("Recovered"))
          nil
        elsif failure_observed && File.binread(manifest) != successful_manifest
          :stop
        end
      end

      status = run_watch(
        ["--manifest", "-o", parser, grammar],
        hook: hook, stderr: errors, sleeper: ->(_seconds) {}
      )

      assert_equal 0, status
      assert_equal 1, errors.string.scan("expected class").length
      assert Ibex::GenerationManifest.validate_file(manifest)
    end
  end

  def test_missing_lexical_include_is_watched_until_it_appears
    Dir.mktmpdir("ibex-watch") do |directory|
      grammar = File.join(directory, "root.y")
      fragment = File.join(directory, "missing.y")
      parser = File.join(directory, "parser.rb")
      manifest = File.join(directory, "parser.ibex.json")
      File.binwrite(grammar, "class P\ninclude \"missing.y\"\nrule\nstart: helper\nend\n")
      errors = StringIO.new
      created = false
      hook = lambda do |event, iteration, paths|
        raise "watch did not converge" if iteration > 8
        next unless event == :after_build
        return :stop if File.exist?(manifest)
        next if created

        assert_includes paths, File.join(File.realpath(directory), File.basename(fragment))
        File.binwrite(fragment, "fragment\nrule\nhelper: TOKEN\nend\n")
        created = true
        nil
      end

      status = run_watch(
        ["--mode=extended", "--manifest", "-o", parser, grammar],
        hook: hook, stderr: errors, sleeper: ->(_seconds) {}
      )

      assert_equal 0, status
      assert_equal 1, errors.string.scan("include file does not exist").length
      assert Ibex::GenerationManifest.validate_file(manifest)
    end
  end

  def test_rejects_incompatible_watch_modes
    Dir.mktmpdir("ibex-watch") do |directory|
      grammar = File.join(directory, "parser.y")
      File.binwrite(grammar, grammar_source("P"))
      {
        ["--watch", "--check", grammar] => /--watch cannot be combined with --check/,
        ["--watch", "--check-only", grammar] => /--watch cannot be combined with --check-only/,
        ["--watch", "--from=grammar-ir", grammar] => /--watch cannot be combined with --from/,
        ["--watch", "--emit=sets", grammar] => /--watch requires --emit=ruby/,
        ["--watch", "--help"] => /--watch cannot be combined with information options/,
        ["--watch", "-"] => /requires a grammar file, not stdin/
      }.each do |arguments, message|
        errors = StringIO.new
        assert_equal 1, Ibex::CLI.start(arguments, stdout: StringIO.new, stderr: errors)
        assert_match message, errors.string
      end
    end
  end

  def test_output_repair_retries_without_a_source_change
    Dir.mktmpdir("ibex-watch") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      alias_path = File.join(directory, "parser.alias")
      manifest = File.join(directory, "parser.ibex.json")
      File.binwrite(grammar, grammar_source("P"))
      File.binwrite(alias_path, "old parser")
      File.link(alias_path, parser)
      errors = StringIO.new
      repaired = false
      hook = lambda do |event, iteration, _paths|
        raise "watch did not converge" if iteration > 8
        next unless event == :after_build
        return :stop if File.exist?(manifest)
        next unless errors.string.include?("multiple hard links") && !repaired

        File.unlink(parser)
        repaired = true
        nil
      end

      status = run_watch(
        ["--manifest", "-o", parser, grammar],
        hook: hook, stderr: errors, sleeper: ->(_seconds) {}
      )

      assert_equal 0, status
      assert repaired
      assert_equal 1, errors.string.scan("multiple hard links").length
      assert Ibex::GenerationManifest.validate_file(manifest)
    end
  end

  def test_process_signals_return_documented_statuses
    %w[INT TERM].zip([130, 143]).each do |signal, expected|
      Dir.mktmpdir("ibex-watch-signal") do |directory|
        grammar = File.join(directory, "parser.y")
        parser = File.join(directory, "parser.rb")
        File.binwrite(grammar, grammar_source("P"))
        pid = Process.spawn(
          RbConfig.ruby, "-I#{File.expand_path('../lib', __dir__)}", File.expand_path("../exe/ibex", __dir__),
          "--watch", "-o", parser, grammar, out: File::NULL, err: File::NULL
        )
        begin
          Timeout.timeout(10) do
            sleep(0.02) until File.exist?(parser)
          end
          Process.kill(signal, pid)
          _waited, status = Process.wait2(pid)
          assert_equal expected, status.exitstatus
          pid = nil
        ensure
          Process.kill("KILL", pid) if pid
          Process.wait(pid) if pid
        end
      end
    end
  end

  private

  def grammar_source(class_name)
    "class #{class_name}\nrule\nstart: TOKEN\nend\n"
  end

  def manifest_input_digest(path)
    JSON.parse(File.binread(path)).dig("input", "sha256")
  end

  def run_watch(arguments, hook:, sleeper:, stderr: StringIO.new)
    Ibex::CLI.start(
      ["--watch", *arguments],
      stdout: StringIO.new,
      stderr: stderr,
      watch_clock: -> { 0.0 },
      watch_sleeper: sleeper,
      watch_iteration_hook: hook
    )
  end
end
# rubocop:enable Metrics/BlockLength, Metrics/MethodLength
