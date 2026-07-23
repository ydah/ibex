# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "open3"
require "rbconfig"

class ExamplesBenchmarkTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "benchmark/examples.rb")

  def test_real_example_generation_and_runtime_benchmark_smoke_run
    command = [
      RbConfig.ruby, SCRIPT,
      "--generation-iterations", "2",
      "--runtime-iterations", "2",
      "--json"
    ]
    stdout, stderr, status = Open3.capture3(*command, chdir: ROOT)
    assert status.success?, "benchmark failed:\n#{stderr}\n#{stdout}"

    report = JSON.parse(stdout)
    assert_equal 2, report.fetch("generation_iterations")
    assert_equal 2, report.fetch("runtime_iterations")
    assert_equal %w[calculator ini json tiny_language], report.fetch("examples").keys.sort
    report.fetch("examples").each_value do |example|
      variants = example.fetch("variants")
      assert_equal 4, variants.length
      assert_equal(
        %w[false:compact false:plain true:compact true:plain],
        variants.map do |variant|
          "#{variant.fetch('line_mapping')}:#{variant.fetch('table')}"
        end.sort
      )
      variants.each do |variant|
        assert_operator variant.fetch("generation_ms"), :>=, 0
        assert_operator variant.fetch("runtime_ms"), :>=, 0
        assert_operator variant.fetch("output_bytes"), :>, 0
        assert_match(/\A[0-9a-f]{64}\z/, variant.fetch("result_sha256"))
      end
    end
  end
end
