# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require "tmpdir"

class WatchRunnerTest < Minitest::Test
  Result = Struct.new(:source_paths, :attempted_paths, keyword_init: true)

  def test_rebuilds_when_source_changes_after_publish_returns
    Dir.mktmpdir("ibex-watch-runner") do |directory|
      source = File.join(directory, "parser.y")
      File.binwrite(source, "A")
      builds = 0
      publishes = 0
      runner = runner(
        source,
        build: lambda {
          builds += 1
          Result.new(source_paths: [source], attempted_paths: [])
        },
        publish: lambda { |_result, _snapshot, _continue|
          publishes += 1
          File.binwrite(source, "B") if publishes == 1
        },
        hook: ->(event, _iteration, _paths) { :stop if event == :after_build && builds == 2 }
      )

      assert_equal 0, runner.run
      assert_equal 2, builds
      assert_equal 2, publishes
    end
  end

  def test_failure_that_changes_source_retries_after_a_bounded_sleep
    Dir.mktmpdir("ibex-watch-runner") do |directory|
      source = File.join(directory, "parser.y")
      File.binwrite(source, "A")
      builds = 0
      sleeps = 0
      errors = StringIO.new
      runner = runner(
        source,
        stderr: errors,
        sleeper: ->(_seconds) { sleeps += 1 },
        build: lambda {
          builds += 1
          if builds == 1
            File.binwrite(source, "B")
            raise Ibex::Error, "transient build failure"
          end
          Result.new(source_paths: [source], attempted_paths: [])
        },
        hook: ->(event, _iteration, _paths) { :stop if event == :after_build && builds == 2 }
      )

      assert_equal 0, runner.run
      assert_equal 2, builds
      assert_operator sleeps, :>, 0
      assert_equal 1, errors.string.scan("transient build failure").length
    end
  end

  def test_repeated_source_changed_retries_are_not_a_busy_loop
    Dir.mktmpdir("ibex-watch-runner") do |directory|
      source = File.join(directory, "parser.y")
      File.binwrite(source, "A")
      builds = 0
      sleeps = 0
      runner = runner(
        source,
        sleeper: ->(_seconds) { sleeps += 1 },
        build: lambda {
          builds += 1
          Result.new(source_paths: [source], attempted_paths: [])
        },
        publish: ->(_result, _snapshot, _continue) { raise Ibex::GenerationTransaction::SourceChanged, "changed" },
        hook: ->(event, _iteration, _paths) { :stop if event == :after_build && builds == 3 }
      )

      assert_equal 0, runner.run
      assert_equal 3, builds
      assert_operator sleeps, :>=, 2
    end
  end

  # The scenario spans two successful generations and a poll to prove pruning.
  # rubocop:disable Metrics/BlockLength, Metrics/MethodLength
  def test_successful_build_prunes_removed_include_from_watch_set
    Dir.mktmpdir("ibex-watch-runner") do |directory|
      root = File.join(directory, "root.y")
      fragment = File.join(directory, "fragment.y")
      File.binwrite(root, "include")
      File.binwrite(fragment, "fragment A")
      builds = 0
      publishes = 0
      polls = 0
      runner = runner(
        root,
        build: lambda {
          builds += 1
          files = File.binread(root) == "include" ? [root, fragment] : [root]
          Result.new(source_paths: files, attempted_paths: [])
        },
        publish: lambda { |_result, _snapshot, _continue|
          publishes += 1
          if publishes == 1
            File.binwrite(root, "plain")
          elsif publishes == 2
            File.binwrite(fragment, "fragment B")
          end
        },
        hook: lambda { |event, _iteration, paths|
          next unless event == :poll

          polls += 1
          assert_equal [File.expand_path(root)], paths
          :stop if polls == 2
        }
      )

      assert_equal 0, runner.run
      assert_equal 3, builds
      assert_equal 2, publishes
    end
  end
  # rubocop:enable Metrics/BlockLength, Metrics/MethodLength

  private

  def runner(path, build:, hook:, publish: ->(_result, _snapshot, _continue) {}, stderr: StringIO.new,
             sleeper: ->(_seconds) {})
    Ibex::Watch::Runner.new(
      paths: [path],
      build: build,
      publish: publish,
      failure_paths: -> { [path] },
      stderr: stderr,
      clock: -> { 0.0 },
      sleeper: sleeper,
      iteration_hook: hook
    )
  end
end
