# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../benchmark/pipeline"
require "json"
require "json_schemer"
require "open3"
require "rbconfig"
require "tmpdir"

class PipelineBenchmarkTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "benchmark/pipeline.rb")
  SCHEMA = File.join(ROOT, "schema/benchmark-v1.schema.json")

  def test_documented_non_json_command_writes_a_valid_current_artifact
    Dir.mktmpdir("ibex-benchmark-test-") do |directory|
      result_path = File.join(directory, "current.json")
      stdout, stderr, status = Open3.capture3(*command(result_path), chdir: ROOT)
      assert status.success?, "benchmark failed:\n#{stderr}\n#{stdout}"

      assert_includes stdout, "runtime parse (plain):"
      assert_includes stdout, "runtime parse (compact):"
      result = JSON.parse(File.read(result_path))
      assert_valid_schema(result)
      assert_valid_schema(JSON.parse(json_stdout(result)))
      assert_equal "ibex_benchmark", result.fetch("artifact")
      assert_equal 1, result.fetch("schema_version")
      assert_equal expected_structure, result.fetch("structure")
      assert_equal(
        "9ce19ee60fed0e8c24747ba77b05ea052864f854fd33e13956a39a17fa8ee98b",
        result.dig("digests", "artifact_sha256")
      )
      assert_equal(
        %w[parse normalize automaton table_plain table_compact codegen_plain codegen_compact],
        result.dig("measurements", "stage_ms").keys
      )
      result.dig("measurements", "runtime_parse_ms").each_value { |value| assert_operator value, :>=, 0 }
    end
  end

  private

  def command(result_path)
    [
      RbConfig.ruby, SCRIPT,
      "--iterations", "1",
      "--runtime-iterations", "10",
      "--seed", "12345",
      "--output", result_path
    ]
  end

  def assert_valid_schema(document)
    errors = JSONSchemer.schema(JSON.parse(File.read(SCHEMA))).validate(document).to_a
    assert_empty errors
  end

  def json_stdout(result)
    report = JSON.parse(JSON.generate(result), symbolize_names: true)
    options = PipelineBenchmark.parse_options(["--json"])
    PipelineBenchmark.render_output(report, json: options.fetch(:json))
  end

  def expected_structure
    {
      "productions" => 139,
      "canonical_intermediate_states" => 1294,
      "final_states" => 250,
      "tables" => {
        "plain" => {
          "action_cells" => 2115, "goto_cells" => 533, "default_cells" => 250,
          "total_cells" => 2898, "bytes" => 47_522
        },
        "compact" => {
          "action_cells" => 5848, "goto_cells" => 1522, "default_cells" => 250,
          "total_cells" => 7620, "bytes" => 51_999
        }
      },
      "generated_output_bytes" => { "plain" => 63_324, "compact" => 68_180 }
    }
  end
end
