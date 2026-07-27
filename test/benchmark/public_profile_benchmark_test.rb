# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../benchmark/public_profile"
require "json_schemer"
require "tmpdir"

# rubocop:disable Metrics/ClassLength -- one fixture-backed suite owns the diagnostic profile protocol.
class PublicProfileBenchmarkTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCHEMA = File.join(ROOT, "schema/public-performance-profile-v1.schema.json")
  ManifestFixture = Struct.new(:workload) do
    def ids
      [workload.fetch("id")]
    end

    def digest
      "a" * 64
    end

    def fetch(_identifier)
      workload
    end
  end

  def test_defaults_profile_every_scenario_in_fresh_processes
    manifest = ManifestFixture.new(fake_workload)
    options = BenchmarkSupport::PublicProfileOptions.parse(
      ["--checkout", "fixture=/tmp/fixture", "--output", "tmp/profile.json"],
      manifest,
      root: ROOT
    )

    assert_equal 1, options.fetch(:runs)
    assert_equal 10_000, options.fetch(:iterations)
    assert_equal ["fixture"], options.fetch(:projects)
    assert_equal(
      %w[cold_generation warm_runtime_reuse warm_runtime_new_instance],
      BenchmarkSupport::PublicProfileReport.configuration(options).fetch(:scenarios)
    )
    assert BenchmarkSupport::PublicProfileReport.configuration(options).fetch(:fresh_process_per_profile)
  end

  def test_diagnostic_output_cannot_enter_formal_results
    manifest = ManifestFixture.new(fake_workload)

    error = assert_raises(OptionParser::InvalidArgument) do
      BenchmarkSupport::PublicProfileOptions.parse(
        [
          "--checkout", "fixture=/tmp/fixture",
          "--output", "benchmark/results/profile.json"
        ],
        manifest,
        root: ROOT
      )
    end

    assert_includes error.message, "must not be written under benchmark/results"
  end

  def test_workspace_preserves_manifest_path_and_runtime_neighbor
    Dir.mktmpdir("public-profile-workspace-test-") do |directory|
      checkout = File.join(directory, "checkout")
      workspace_root = File.join(directory, "workspace")
      grammar = File.join(checkout, "lib/nokogiri/css/parser.y")
      extras = File.join(checkout, "lib/nokogiri/css/parser_extras.rb")
      FileUtils.mkdir_p(File.dirname(grammar))
      File.write(grammar, "class Parser\nrule\nend\n")
      File.write(extras, "module Extras\nend\n")
      workload = fake_workload.merge(
        "id" => "nokogiri_css",
        "grammar_path" => "lib/nokogiri/css/parser.y"
      )

      workspace = BenchmarkSupport::PublicWorkloadWorkspace.new(
        directory: workspace_root, workload: workload, checkout: checkout
      ).prepare

      assert_equal File.join(workspace_root, "lib/nokogiri/css/parser.y"), workspace.grammar
      assert_equal File.join(workspace_root, "lib/nokogiri/css/parser.rb"), workspace.output
      assert_equal File.read(grammar), File.read(workspace.grammar)
      assert_equal File.read(extras), File.read(File.join(workspace_root, "lib/nokogiri/css/parser_extras.rb"))
    end
  end

  def test_profiled_generation_changes_only_the_launcher
    workspace = Struct.new(:output, :grammar).new("/tmp/workspace/parser.rb", "/tmp/workspace/parser.y")
    formal = BenchmarkSupport::PublicComparisonWorker.command_for("ibex", "parser.rb", "parser.y")
    profiled = PublicPerformanceProfile.profiled_generation_command(workspace)
    executable = File.join(ROOT, "exe/ibex")
    launcher_index = formal.index(executable)

    assert launcher_index
    assert_equal formal.values_at(*(0...formal.length).to_a - [launcher_index]),
                 profiled.values_at(*(0...profiled.length).to_a - [launcher_index])
    assert_equal PublicPerformanceProfile::PROFILE_GENERATOR, profiled.fetch(launcher_index)
  end

  def test_top_frame_paths_are_portable
    checkout = "/tmp/public-checkout"
    workspace = "/tmp/profile-workspace"
    grammar = File.join(workspace, "lib/parser.y")
    output = File.join(workspace, "lib/parser.rb")
    metadata = {
      "top_frames" => [
        { "file" => File.join(ROOT, "lib/ibex.rb") },
        { "file" => File.join(checkout, "lib/support.rb") },
        { "file" => output },
        { "file" => grammar },
        { "file" => "<cfunc>" },
        { "file" => "" },
        { "file" => nil }
      ]
    }

    normalized = PublicPerformanceProfile.normalize_profile_metadata(
      metadata, checkout: checkout, workspace: workspace, grammar: grammar, output: output
    )

    assert_equal(
      [
        "<repository>/lib/ibex.rb",
        "<checkout>/lib/support.rb",
        "<generated-parser>",
        "<public-grammar>",
        "<cfunc>",
        nil,
        nil
      ],
      normalized.fetch("top_frames").map { |frame| frame.fetch("file") }
    )
  end

  def test_top_frame_paths_normalize_filesystem_canonicalization
    Dir.mktmpdir("public-profile-path-test-") do |directory|
      grammar = File.join(directory, "parser.y")
      output = File.join(directory, "parser.rb")
      File.write(grammar, "rule\n")
      File.write(output, "# generated\n")
      canonical_output = File.join(File.realpath(directory), "parser.rb")

      normalized = PublicPerformanceProfile.normalize_profile_path(
        canonical_output,
        checkout: File.join(directory, "checkout"),
        workspace: directory,
        grammar: grammar,
        output: output
      )

      assert_equal "<generated-parser>", normalized
    end
  end

  def test_report_is_strictly_diagnostic_and_schema_valid
    report = build_report
    errors = JSONSchemer.schema(JSON.parse(File.read(SCHEMA))).validate(JSON.parse(JSON.generate(report))).to_a

    assert_empty errors
    assert_same report, PublicPerformanceProfile.validate_report!(report)
    refute report.fetch(:formal_evidence)
    assert_equal "diagnostic_profile", report.fetch(:evidence_kind)
    refute report.dig(:profiler, :timing_comparable)
  end

  def test_schema_rejects_formal_or_target_claims
    report = build_report
    report[:formal_evidence] = true
    assert_raises(RuntimeError) { PublicPerformanceProfile.validate_report!(report) }

    report = build_report
    report[:target_met] = true
    assert_raises(RuntimeError) { PublicPerformanceProfile.validate_report!(report) }
  end

  def test_report_rejects_missing_profile_runs
    report_arguments = fake_report_arguments
    report_arguments.fetch(:options)[:runs] = 2
    profiles = report_arguments.fetch(:profiles).fetch("fixture")
    profiles.concat(profiles.map { |profile| profile.merge("run" => 2) })
    profiles.pop

    error = assert_raises(RuntimeError) do
      BenchmarkSupport::PublicProfileReport.build(**report_arguments)
    end

    assert_includes error.message, "profile runs do not match"
  end

  def test_profile_equivalence_rejects_runtime_result_changes
    profiles = { "fixture" => fake_profiles }
    assert_same profiles, PublicPerformanceProfile.verify_profile_equivalence!(profiles)
    profiles.fetch("fixture").last["result_sequence_sha256"] = "9" * 64

    error = assert_raises(RuntimeError) do
      PublicPerformanceProfile.verify_profile_equivalence!(profiles)
    end
    assert_includes error.message, "result_sequence_sha256 changed"
  end

  private

  def build_report
    BenchmarkSupport::PublicProfileReport.build(**fake_report_arguments)
  end

  def fake_report_arguments
    options = {
      projects: ["fixture"],
      runs: 1,
      warmup: 50,
      iterations: 10_000,
      interval_usec: 1_000,
      top_frames: 20,
      allow_dirty: true
    }
    {
      options: options,
      manifest: ManifestFixture.new(fake_workload),
      checkouts: { "fixture" => fake_checkout },
      profiles: { "fixture" => fake_profiles },
      environment: fake_environment,
      formal_commands: {
        "fixture" => {
          generation: ["ruby", "exe/ibex", "--output-file=<generated-output>", "<public-grammar>"],
          workers: PublicPerformanceProfile::SCENARIOS.to_h { |scenario| [scenario, ["ruby", scenario]] }
        }
      }
    }
  end

  def fake_profiles
    PublicPerformanceProfile::SCENARIOS.map do |scenario|
      profile = fake_profile(scenario)
      next profile if scenario == "cold_generation"

      profile.merge(
        "result_sha256" => "d" * 64,
        "result_sequence_sha256" => "e" * 64,
        "result_sequence_length" => 5
      )
    end
  end

  def fake_profile(scenario)
    {
      "scenario" => scenario,
      "run" => 1,
      "command" => ["ruby", "<repository>/benchmark/profile.rb"],
      "raw_profile" => "profile.profiles/#{scenario}.dump",
      "raw_profile_sha256" => "b" * 64,
      "outer_elapsed_ms" => 1.0,
      "profiled_region_elapsed_ms" => 0.5,
      "profiler_name" => "stackprof",
      "profiler_version" => "0.2.28",
      "yjit_enabled" => false,
      "rubyopt_sha256" => nil,
      "samples" => 1,
      "missed_samples" => 0,
      "gc_samples" => 0,
      "top_frames" => [fake_frame],
      "generated_bytes" => 100,
      "generated_sha256" => "c" * 64
    }
  end

  def fake_frame
    {
      "name" => "Fixture#parse",
      "file" => "<generated-parser>",
      "line" => 1,
      "total_samples" => 1,
      "self_samples" => 1
    }
  end

  def fake_workload
    {
      "id" => "fixture",
      "repository_url" => "https://example.com/project.git",
      "revision" => "1" * 40,
      "grammar_path" => "lib/parser.y",
      "dependency_definition_path" => "Gemfile",
      "driver" => "fixture",
      "workload_id" => "fixture-v1",
      "inputs" => ["value"]
    }
  end

  def fake_checkout
    {
      root: "/tmp/not-recorded",
      origin: "https://example.com/project.git",
      revision: "1" * 40,
      dirty: true,
      tracked_dirty: true,
      untracked_dirty: false,
      status_sha256: "2" * 64,
      grammar_sha256: "3" * 64,
      dependency_definition_sha256: "4" * 64,
      library_tree_oid: "5" * 40
    }
  end

  def fake_environment
    {
      git_revision: "6" * 40,
      git_dirty: true,
      git_tracked_dirty: true,
      git_untracked_dirty: false,
      ruby_engine: "ruby",
      ruby_version: "4.0.0",
      ruby_platform: "arm64-darwin",
      ruby_description: "ruby 4.0.0",
      ruby_executable: "/usr/bin/ruby",
      host_os: "darwin",
      host_cpu: "arm64",
      kernel_release: "25.0.0",
      processors: 8,
      yjit_available: true,
      yjit_enabled: false,
      ibex_version: Ibex::VERSION,
      rubyopt: { present: false, bytes: 0, sha256: nil, sanitized: [] }
    }
  end
end
# rubocop:enable Metrics/ClassLength
