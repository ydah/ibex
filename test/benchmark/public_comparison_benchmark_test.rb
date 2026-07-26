# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../benchmark/public_comparison"
require_relative "../../benchmark/support/public_comparison_report"
require "json_schemer"
require "tmpdir"

class PublicComparisonBenchmarkTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCHEMA = File.join(ROOT, "schema/public-performance-comparison-v1.schema.json")

  def test_manifest_fixes_all_public_projects_and_revisions
    manifest = BenchmarkSupport::PublicWorkloadManifest.new(PublicPerformanceComparison::MANIFEST)

    assert_equal %w[namae bcdice_command nokogiri_css], manifest.ids
    assert_equal(
      "d33875aaf1fc420a8dfe946a3b29cc3e19710061",
      manifest.fetch("namae").fetch("revision")
    )
    manifest.ids.each do |identifier|
      workload = manifest.fetch(identifier)
      assert_match(/\A[0-9a-f]{40}\z/, workload.fetch("revision"))
      assert_operator workload.fetch("inputs").length, :>=, 5
    end
  end

  def test_formal_reports_require_ten_runs_and_smoke_is_explicit
    error = assert_raises(OptionParser::InvalidArgument) do
      PublicPerformanceComparison.parse_options(["--runs", "9"])
    end
    options, = PublicPerformanceComparison.parse_options(["--smoke"])

    assert_includes error.message, "at least ten isolated runs"
    assert options.fetch(:smoke)
    assert_equal 1, options.fetch(:runs)
    assert_equal 1_000, options.fetch(:bootstrap_samples)
  end

  def test_manifest_rejects_parent_traversal
    Dir.mktmpdir("public-workload-manifest-test-") do |directory|
      path = File.join(directory, "manifest.json")
      document = JSON.parse(File.read(PublicPerformanceComparison::MANIFEST))
      document.fetch("workloads").first["grammar_path"] = "../parser.y"
      File.write(path, JSON.generate(document))

      error = assert_raises(RuntimeError) { BenchmarkSupport::PublicWorkloadManifest.new(path) }
      assert_includes error.message, "relative and normalized"
    end
  end

  def test_report_validates_against_its_separate_schema
    options, manifest = PublicPerformanceComparison.parse_options(["--smoke", "--project", "namae"])
    options[:allow_dirty] = true
    checkouts = { "namae" => fake_checkout }
    observations = { "namae" => fake_observations }
    report = BenchmarkSupport::PublicComparisonReport.build(options, manifest, checkouts, observations)
    errors = JSONSchemer.schema(JSON.parse(File.read(SCHEMA))).validate(JSON.parse(JSON.generate(report))).to_a

    assert_empty errors
    assert_same report, PublicPerformanceComparison.validate_report!(report)
    assert_equal "diagnostic_smoke", report.fetch(:evidence_kind)
    assert_equal "end_to_end_lexer_inclusive", report.dig(:configuration, :runtime_scope)
    assert report.dig(:projects, 0, :scenarios, :warm_runtime_reuse, :comparison, :result_equivalent)
  end

  def test_worker_command_preserves_yjit_mode_and_checkout_as_one_argument
    options, = PublicPerformanceComparison.parse_options(["--smoke"])
    command = PublicPerformanceComparison.worker_command(
      "ibex", "warm_runtime_reuse", "namae", "/tmp/a checkout", options
    )

    assert_includes command, "/tmp/a checkout"
    assert_includes command, BenchmarkSupport::ComparisonWorker.yjit_enabled? ? "--yjit" : "--disable-yjit" if
      defined?(RubyVM::YJIT)
  end

  private

  def fake_checkout
    {
      root: "/tmp/not-recorded",
      origin: "https://github.com/berkmancenter/namae.git",
      revision: "d33875aaf1fc420a8dfe946a3b29cc3e19710061",
      dirty: true,
      tracked_dirty: true,
      untracked_dirty: false,
      status_sha256: "a" * 64,
      grammar_sha256: "b" * 64,
      lockfile_sha256: "c" * 64,
      tracked_library_sha256: "d" * 64
    }
  end

  def fake_observations
    BenchmarkSupport::PublicComparisonWorker::SCENARIOS.to_h do |scenario|
      implementations = %w[ibex racc].to_h do |implementation|
        [implementation, [fake_observation(scenario, implementation)]]
      end
      [scenario, implementations]
    end
  end

  def fake_observation(scenario, implementation)
    common = {
      "implementation" => implementation,
      "scenario" => scenario,
      "generated_bytes" => implementation == "ibex" ? 120 : 100,
      "yjit_enabled" => BenchmarkSupport::ComparisonWorker.yjit_enabled?,
      "rubyopt_sha256" => BenchmarkSupport::ComparisonWorker.rubyopt_metadata.fetch(:sha256)
    }
    return common.merge("elapsed_ms" => implementation == "ibex" ? 2.0 : 1.0) if scenario == "cold_generation"

    common.merge(
      "elapsed_ms_per_parse" => implementation == "ibex" ? 2.0 : 1.0,
      "allocated_objects_per_parse" => implementation == "ibex" ? 20.0 : 10.0,
      "result_sha256" => "e" * 64,
      "result_sequence_sha256" => "f" * 64,
      "result_sequence_length" => 2,
      "runtime_backend" => implementation == "ibex" ? "ruby" : "native"
    )
  end
end
