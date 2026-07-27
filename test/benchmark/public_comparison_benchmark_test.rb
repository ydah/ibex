# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../benchmark/public_comparison"
require_relative "../../benchmark/support/public_comparison_report"
require "json_schemer"
require "tmpdir"

class PublicComparisonRootIdentityTest < Minitest::Test
  def test_repository_root_identity_must_not_change_during_collection
    options, = PublicPerformanceComparison.parse_options(["--smoke"])
    before = {
      git_revision: "1" * 40,
      git_dirty: false,
      git_tracked_dirty: false,
      git_untracked_dirty: false
    }
    assert_same before, PublicPerformanceComparison.assert_root_unchanged!(before, before, options)

    PublicPerformanceComparison::ROOT_IDENTITY_KEYS.each do |key|
      after = before.dup
      after[key] = key == :git_revision ? "2" * 40 : true
      error = assert_raises(RuntimeError) do
        PublicPerformanceComparison.assert_root_unchanged!(before, after, options)
      end
      assert_includes error.message, "changed during observation collection"
    end
  end
end

class PublicComparisonDependencyDefinitionTest < Minitest::Test
  def test_ignored_lockfile_cannot_replace_a_tracked_dependency_definition
    Dir.mktmpdir("public-dependency-definition-test-") do |directory|
      checkout = File.join(directory, "checkout")
      prepare_checkout(checkout)
      revision = git(checkout, "rev-parse", "HEAD")
      manifest_path = File.join(directory, "manifest.json")

      write_manifest(manifest_path, revision, "Gemfile.lock")
      manifest = BenchmarkSupport::PublicWorkloadManifest.new(manifest_path)
      error = assert_raises(RuntimeError) do
        manifest.verify_checkout("fixture", checkout, allow_dirty: false)
      end
      assert_includes error.message, "must be tracked at HEAD"

      write_manifest(manifest_path, revision, "Gemfile")
      manifest = BenchmarkSupport::PublicWorkloadManifest.new(manifest_path)
      metadata = manifest.verify_checkout("fixture", checkout, allow_dirty: false)
      assert_equal Digest::SHA256.file(File.join(checkout, "Gemfile")).hexdigest,
                   metadata.fetch(:dependency_definition_sha256)
      refute metadata.fetch(:dirty)
    end
  end

  private

  def prepare_checkout(checkout)
    FileUtils.mkdir_p(File.join(checkout, "lib"))
    git(checkout, "init", "--quiet")
    git(checkout, "config", "user.email", "benchmark@example.com")
    git(checkout, "config", "user.name", "Benchmark Fixture")
    File.write(File.join(checkout, ".gitignore"), "Gemfile.lock\n")
    File.write(File.join(checkout, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(checkout, "Gemfile.lock"), "ignored local lock\n")
    File.write(File.join(checkout, "lib/parser.y"), "class FixtureParser\nrule\nend\n")
    git(checkout, "add", ".")
    git(checkout, "commit", "--quiet", "-m", "Add fixture")
    git(checkout, "remote", "add", "origin", "https://example.com/project.git")
  end

  def write_manifest(path, revision, dependency_definition_path)
    document = {
      schema_version: 1,
      workloads: [{
        id: "fixture",
        repository_url: "https://example.com/project.git",
        revision: revision,
        grammar_path: "lib/parser.y",
        dependency_definition_path: dependency_definition_path,
        driver: "namae",
        workload_id: "fixture-v1",
        inputs: ["Ada Lovelace"]
      }]
    }
    File.write(path, JSON.generate(document))
  end

  def git(directory, *arguments)
    FileUtils.mkdir_p(directory)
    stdout, stderr, status = Open3.capture3("git", *arguments, chdir: directory)
    raise "fixture git command failed: #{stderr}#{stdout}" unless status.success?

    stdout.strip
  end
end

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
      assert_equal "Gemfile", workload.fetch("dependency_definition_path")
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

  def test_formal_reports_require_ruby_racc
    error = assert_raises(OptionParser::InvalidArgument) do
      PublicPerformanceComparison.parse_options(["--expected-racc-backend", "native"])
    end
    options, = PublicPerformanceComparison.parse_options(
      ["--smoke", "--expected-racc-backend", "native"]
    )

    assert_includes error.message, "formal reports require Racc's Ruby backend"
    assert_equal "native", options.fetch(:expected_racc_backend)
    assert_equal "ruby", PublicPerformanceComparison.parse_options([]).first.fetch(:expected_racc_backend)
  end

  def test_formal_reports_reject_a_dirty_repository_root
    options, = PublicPerformanceComparison.parse_options([])
    environment = {
      git_dirty: true,
      git_tracked_dirty: false,
      git_untracked_dirty: true
    }

    error = assert_raises(RuntimeError) do
      PublicPerformanceComparison.verify_root!(options, environment)
    end
    assert_includes error.message, "clean Ibex repository root"
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
    environment = PerformanceComparison.environment
    report = build_smoke_report(environment: environment)
    errors = JSONSchemer.schema(JSON.parse(File.read(SCHEMA))).validate(JSON.parse(JSON.generate(report))).to_a

    assert_empty errors
    assert_same report, PublicPerformanceComparison.validate_report!(report)
    assert_same environment, report.fetch(:environment)
    assert_equal "diagnostic_smoke", report.fetch(:evidence_kind)
    assert_equal "end_to_end_lexer_inclusive", report.dig(:configuration, :runtime_scope)
    assert report.dig(:projects, 0, :scenarios, :warm_runtime_reuse, :comparison, :result_equivalent)
  end

  def test_schema_rejects_a_smoke_artifact_relabelled_as_formal
    report = build_smoke_report
    report[:evidence_kind] = "formal"

    error = assert_raises(RuntimeError) { PublicPerformanceComparison.validate_report!(report) }
    assert_includes error.message, "violates its schema"
  end

  def test_schema_accepts_only_complete_clean_ruby_formal_evidence
    report = build_smoke_report
    formalize!(report)

    assert_same report, PublicPerformanceComparison.validate_report!(report)

    report.dig(:projects, 0, :scenarios, :warm_runtime_reuse, :implementations, :racc)[:runtime_backend] = "native"
    assert_raises(RuntimeError) { PublicPerformanceComparison.validate_report!(report) }
  end

  def test_report_builder_requires_the_configured_observation_count
    options, manifest = PublicPerformanceComparison.parse_options(["--smoke", "--project", "namae"])
    options[:runs] = 2

    error = assert_raises(RuntimeError) do
      BenchmarkSupport::PublicComparisonReport.build(
        options,
        manifest,
        { "namae" => fake_checkout },
        { "namae" => fake_observations },
        environment: PerformanceComparison.environment
      )
    end
    assert_includes error.message, "has 1 observations; expected 2"
  end

  def test_checkout_metadata_must_not_change_during_collection
    before = { "namae" => fake_checkout }
    assert_same before, PublicPerformanceComparison.assert_checkouts_unchanged!(before, before)

    after = Marshal.load(Marshal.dump(before))
    after.fetch("namae")[:grammar_sha256] = "9" * 64
    error = assert_raises(RuntimeError) do
      PublicPerformanceComparison.assert_checkouts_unchanged!(before, after)
    end
    assert_includes error.message, "namae"
  end

  def test_checkout_identity_uses_the_git_tree_without_reading_tracked_files
    source = File.read(File.join(ROOT, "benchmark/support/public_workload_manifest.rb"))

    assert_includes source, '"HEAD:lib"'
    assert_includes source, '"ls-tree"'
    refute_includes source, "File.binread"
    refute_includes source, "tracked_library_sha256"
  end

  def test_worker_command_preserves_yjit_mode_and_checkout_as_one_argument
    options, = PublicPerformanceComparison.parse_options(["--smoke"])
    command = PublicPerformanceComparison.worker_command(
      "ibex", "warm_runtime_reuse", "namae", "/tmp/a checkout", options
    )

    assert_includes command, "/tmp/a checkout"
    assert_equal "ruby", command.last
    assert_includes command, BenchmarkSupport::ComparisonWorker.yjit_enabled? ? "--yjit" : "--disable-yjit" if
      defined?(RubyVM::YJIT)
  end

  private

  def build_smoke_report(environment: PerformanceComparison.environment)
    options, manifest = PublicPerformanceComparison.parse_options(["--smoke", "--project", "namae"])
    options[:allow_dirty] = true
    BenchmarkSupport::PublicComparisonReport.build(
      options,
      manifest,
      { "namae" => fake_checkout },
      { "namae" => fake_observations },
      environment: environment
    )
  end

  def formalize!(report)
    report[:evidence_kind] = "formal"
    report[:configuration][:runs] = 10
    report[:configuration][:allow_dirty_checkouts] = false
    %i[git_dirty git_tracked_dirty git_untracked_dirty].each { |key| report[:environment][key] = false }
    repository = report.dig(:projects, 0, :repository)
    %i[dirty tracked_dirty untracked_dirty].each { |key| repository[key] = false }
    report.dig(:projects, 0, :scenarios).each_value do |scenario|
      scenario.fetch(:implementations).each_value do |implementation|
        implementation.fetch(:observations).transform_values! { |values| Array.new(10, values.first) }
      end
    end
  end

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
      dependency_definition_sha256: "c" * 64,
      library_tree_oid: "d" * 40
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
      "runtime_backend" => "ruby"
    )
  end
end
