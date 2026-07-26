# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../benchmark/pipeline"
require "digest"
require "json"
require "json_schemer"
require "open3"
require "rbconfig"
require "tmpdir"

class PipelineBenchmarkTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "benchmark/pipeline.rb")
  SCHEMA = File.join(ROOT, "schema/benchmark-v2.schema.json")

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
      assert_equal 2, result.fetch("schema_version")
      structure = result.fetch("structure")
      generated_sizes = structure.fetch("generated_output_bytes")
      assert_equal expected_structure, structure.except("generated_output_bytes")
      generated_sizes.each_value { |bytes| assert_operator bytes, :>, 0 }
      assert_digest_is_self_consistent(result.fetch("digests"))
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
    resolver = lambda do |uri|
      path = File.join(ROOT, "schema", File.basename(uri.path))
      JSON.parse(File.read(path)) if File.file?(path)
    end
    errors = JSONSchemer.schema(JSON.parse(File.read(SCHEMA)), ref_resolver: resolver).validate(document).to_a
    assert_empty errors
  end

  def json_stdout(result)
    report = JSON.parse(JSON.generate(result), symbolize_names: true)
    options = PipelineBenchmark.parse_options(["--json"])
    PipelineBenchmark.render_output(report, json: options.fetch(:json))
  end

  def assert_digest_is_self_consistent(digests)
    component_digests = digests.except("artifact_sha256")
    expected = Digest::SHA256.hexdigest(JSON.generate(component_digests))

    assert_equal expected, digests.fetch("artifact_sha256")
  end

  def expected_structure
    {
      "productions" => 139,
      "construction_strategy" => "direct_lalr",
      "construction_intermediate_states" => 250,
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
      }
    }
  end
end
