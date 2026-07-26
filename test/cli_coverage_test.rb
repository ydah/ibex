# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "json_schemer"
require "stringio"
require "tmpdir"

class CLICoverageTest < Minitest::Test
  DIGEST = "sha256:#{'c' * 64}".freeze
  SCHEMA = JSONSchemer.schema(
    JSON.parse(File.read(File.expand_path("../schema/runtime-coverage-v1.schema.json", __dir__)))
  )

  def test_collect_and_merge_are_deterministic
    Dir.mktmpdir do |directory|
      events = File.join(directory, "events.jsonl")
      first = File.join(directory, "first.json")
      merged = File.join(directory, "merged.json")
      write_events(events)

      assert_equal 0, run_cli(["coverage", "collect", events, "-o", first])
      first_document = JSON.parse(File.read(first))
      assert_empty SCHEMA.validate(first_document).to_a
      state_ids = first_document.fetch("state_hits").map { |hit| hit.fetch("id") }
      production_ids = first_document.fetch("production_hits").map { |hit| hit.fetch("id") }
      assert_equal [0, 2, 3], state_ids
      assert_equal [1], production_ids

      assert_equal 0, run_cli(["coverage", "merge", first, first, "-o", merged])
      merged_document = JSON.parse(File.read(merged))
      assert_equal 4, merged_document.fetch("sessions")
      state_counts = merged_document.fetch("state_hits").map { |hit| hit.fetch("count") }
      assert_equal [4, 2, 4], state_counts
    end
  end

  def test_threshold_check_reports_success_and_failure
    Dir.mktmpdir do |directory|
      events = File.join(directory, "events.jsonl")
      report = File.join(directory, "report.json")
      write_events(events)
      assert_equal 0, run_cli(["coverage", "collect", events, "-o", report])

      output = StringIO.new
      assert_equal 0, run_cli(
        ["coverage", "check", report, "--min-states=50", "--min-productions=25"],
        stdout: output
      )
      assert_includes output.string, "coverage ok: states 60.00% (3/5), productions 25.00% (1/4)"

      errors = StringIO.new
      assert_equal 1, run_cli(["coverage", "check", report, "--min-states=61"], stderr: errors)
      assert_includes errors.string, "coverage failed"
    end
  end

  def test_collect_and_merge_write_to_stdout_without_output_option
    Dir.mktmpdir do |directory|
      events = File.join(directory, "events.jsonl")
      report = File.join(directory, "report.json")
      write_events(events)

      collected = StringIO.new
      assert_equal 0, run_cli(["coverage", "collect", events], stdout: collected)
      JSON.parse(collected.string)
      File.write(report, collected.string)

      merged = StringIO.new
      assert_equal 0, run_cli(["coverage", "merge", report], stdout: merged)
      assert_equal JSON.parse(collected.string), JSON.parse(merged.string)
    end
  end

  def test_rejects_invalid_operations_thresholds_arity_and_path_collisions
    Dir.mktmpdir do |directory|
      events = File.join(directory, "events.jsonl")
      report = File.join(directory, "report.json")
      write_events(events)
      run_cli(["coverage", "collect", events, "-o", report])

      cases = [
        ["coverage"],
        ["coverage", "unknown"],
        ["coverage", "collect"],
        ["coverage", "collect", events, events],
        ["coverage", "collect", events, "-o", events],
        ["coverage", "merge"],
        ["coverage", "merge", report, "-o", report],
        ["coverage", "check", report, "--min-states=101"],
        ["coverage", "check", report, "--min-productions=-1"]
      ]
      cases.each do |arguments|
        assert_equal 1, run_cli(arguments), arguments.inspect
      end
    end
  end

  def test_atomic_output_preserves_mode_and_symlink
    Dir.mktmpdir do |directory|
      events = File.join(directory, "events.jsonl")
      target = File.join(directory, "target.json")
      output = File.join(directory, "output.json")
      write_events(events)
      File.write(target, "old\n")
      File.chmod(0o640, target)
      File.symlink(target, output)

      assert_equal 0, run_cli(["coverage", "collect", events, "-o", output])
      assert File.symlink?(output)
      assert_equal 0o640, File.stat(target).mode & 0o777
      assert_equal "runtime-coverage", JSON.parse(File.read(target)).fetch("ibex_coverage")
      assert_equal %w[events.jsonl output.json target.json], Dir.children(directory).sort
    end
  end

  private

  def run_cli(arguments, stdout: StringIO.new, stderr: StringIO.new)
    Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
  end

  def write_events(path)
    File.open(path, "w") do |file|
      file.puts(JSON.generate(event(1, "start", start_data)))
      file.puts(JSON.generate(event(2, "shift", { "state" => 3 })))
      file.puts(JSON.generate(event(3, "reduce", { "production_id" => 1, "goto_state" => 2 })))
      file.puts(JSON.generate(event(4, "accept", {})))
      file.puts(JSON.generate(event(1, "start", start_data)))
      file.puts(JSON.generate(event(2, "shift", { "state" => 3 })))
      file.puts(JSON.generate(event(3, "accept", {})))
    end
  end

  def event(sequence, type, data)
    {
      "ibex_runtime_event" => "runtime-event",
      "schema_version" => 1,
      "sequence" => sequence,
      "event" => type,
      "data" => default_event_data(type).merge(data)
    }
  end

  def default_event_data(type)
    token = { "state" => 0, "token_id" => 2, "token" => "TOKEN", "value" => nil, "location" => nil }
    case type
    when "shift" then token.merge("from_state" => 0)
    when "reduce"
      {
        "production_id" => 0, "lhs" => 5, "rhs_length" => 1,
        "pre_state" => 1, "post_state" => 0, "goto_state" => 1,
        "result" => nil, "location" => nil
      }
    when "accept" then { "state" => 0, "result" => nil, "reason" => "table" }
    else {}
    end
  end

  def start_data
    {
      "driver" => "pull",
      "initial_state" => 0,
      "table_format_version" => 3,
      "grammar_digest" => DIGEST,
      "state_count" => 5,
      "production_count" => 4
    }
  end
end
