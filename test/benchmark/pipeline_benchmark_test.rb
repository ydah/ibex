# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "open3"
require "rbconfig"

class PipelineBenchmarkTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "benchmark/pipeline.rb")

  def test_whole_builder_benchmark_smoke_run
    command = [RbConfig.ruby, SCRIPT, "--rules", "6", "--iterations", "2", "--seed", "4242", "--json"]
    stdout, stderr, status = Open3.capture3(*command, chdir: ROOT)
    assert status.success?, "benchmark failed:\n#{stderr}\n#{stdout}"

    result = JSON.parse(stdout)
    assert_equal 6, result.fetch("grammar_rules")
    assert_equal 13, result.fetch("productions")
    assert_equal %w[parse normalize lalr table codegen_with_tables], result.fetch("stage_ms").keys
    assert_operator result.fetch("states"), :>, 0
    assert_operator result.fetch("output_bytes"), :>, 0
    assert_match(/\A[0-9a-f]{64}\z/, result.fetch("result_sha256"))
  end
end
