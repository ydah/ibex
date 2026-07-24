# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "json"
require "json_schemer"
require "open3"
require "rbconfig"

class PipelineBenchmarkTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "benchmark/pipeline.rb")
  RESULT = File.join(ROOT, "tmp/benchmark-current.json")
  SCHEMA = File.join(ROOT, "schema/benchmark-v1.schema.json")

  def test_documented_non_json_command_writes_a_valid_current_artifact
    command = [
      RbConfig.ruby, SCRIPT,
      "--iterations", "1",
      "--runtime-iterations", "10",
      "--seed", "12345",
      "--output", "tmp/benchmark-current.json"
    ]
    stdout, stderr, status = Open3.capture3(*command, chdir: ROOT)
    assert status.success?, "benchmark failed:\n#{stderr}\n#{stdout}"

    assert_includes stdout, "runtime parse (plain):"
    assert_includes stdout, "runtime parse (compact):"
    result = JSON.parse(File.read(RESULT))
    errors = JSONSchemer.schema(JSON.parse(File.read(SCHEMA))).validate(result).to_a
    assert_empty errors
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
  ensure
    FileUtils.rm_f(RESULT)
  end

  private

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
