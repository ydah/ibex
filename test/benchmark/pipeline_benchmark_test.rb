# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "open3"
require "rbconfig"

class PipelineBenchmarkTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "benchmark/pipeline.rb")

  def test_whole_builder_benchmark_smoke_run
    command = [
      RbConfig.ruby, SCRIPT,
      "--iterations", "1",
      "--runtime-iterations", "2",
      "--seed", "4242",
      "--json"
    ]
    stdout, stderr, status = Open3.capture3(*command, chdir: ROOT)
    assert status.success?, "benchmark failed:\n#{stderr}\n#{stdout}"

    result = JSON.parse(stdout)
    assert_equal "ibex_benchmark", result.fetch("artifact")
    assert_equal 1, result.fetch("schema_version")
    assert_equal expected_structure, result.fetch("structure")
    assert_equal(
      "db62251ec64074accdb6efbb246e8aec98e78ac7e7ae5f7d48e6210a706dc7ec",
      result.dig("digests", "artifact_sha256")
    )
    assert_equal(
      %w[parse normalize automaton table_plain table_compact codegen_plain codegen_compact],
      result.dig("measurements", "stage_ms").keys
    )
    result.dig("measurements", "runtime_parse_ms").each_value { |value| assert_operator value, :>=, 0 }
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
