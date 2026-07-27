#!/usr/bin/env ruby
# frozen_string_literal: true

require "etc"
require "fileutils"
require "json"
require "json_schemer"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../lib/ibex/version"
require_relative "public_comparison"
require_relative "support/public_profile_options"
require_relative "support/public_profile_report"
require_relative "support/public_workload_workspace"

# rubocop:disable Metrics/ModuleLength -- this executable owns one complete diagnostic protocol.
module PublicPerformanceProfile
  ROOT = File.expand_path("..", __dir__)
  MANIFEST = File.join(ROOT, "benchmark/public_workloads.json")
  SCHEMA = File.join(ROOT, "schema/public-performance-profile-v1.schema.json")
  PROFILE_GENERATOR = File.join(ROOT, "benchmark/support/profiled_ibex.rb")
  PROFILE_RUNTIME = File.join(ROOT, "benchmark/support/profiled_public_runtime.rb")
  SCENARIOS = %w[cold_generation warm_runtime_reuse warm_runtime_new_instance].freeze
  IDENTITY_KEYS = %i[git_revision git_dirty git_tracked_dirty git_untracked_dirty].freeze

  module_function

  def run(arguments)
    manifest = BenchmarkSupport::PublicWorkloadManifest.new(MANIFEST)
    options = BenchmarkSupport::PublicProfileOptions.parse(arguments, manifest, root: ROOT)
    warn "WARNING: #{BenchmarkSupport::PublicProfileReport::WARNING}"
    warn "WARNING: #{PublicPerformanceComparison::THIRD_PARTY_WARNING}"
    output, profile_directory = output_paths(options.fetch(:output))
    reject_existing_outputs!(output, profile_directory)

    initial_environment = environment
    verify_root!(initial_environment, allow_dirty: options.fetch(:allow_dirty))
    checkouts = verify_checkouts(options, manifest)
    Dir.mktmpdir("ibex-public-profiles-") do |temporary|
      temporary_profiles = collect_profiles(options, manifest, checkouts, temporary)
      verify_profile_equivalence!(temporary_profiles)
      verified_checkouts = verify_checkouts(options, manifest)
      assert_unchanged!("public checkouts", checkouts, verified_checkouts)
      final_environment = environment
      assert_root_unchanged!(initial_environment, final_environment)
      verify_root!(final_environment, allow_dirty: options.fetch(:allow_dirty))
      report = build_report(
        options, manifest, checkouts, temporary_profiles, final_environment, profile_directory
      )
      validate_report!(report)
      publish(output, profile_directory, report, temporary_profiles)
    end
    puts JSON.pretty_generate(JSON.parse(File.read(output)))
  end

  def verify_checkouts(options, manifest)
    options.fetch(:projects).to_h do |identifier|
      root = options.fetch(:checkouts).fetch(identifier)
      [identifier, manifest.verify_checkout(identifier, root, allow_dirty: options.fetch(:allow_dirty))]
    end
  end

  def collect_profiles(options, manifest, checkouts, temporary)
    options.fetch(:projects).to_h do |identifier|
      workload = manifest.fetch(identifier)
      checkout = checkouts.fetch(identifier).fetch(:root)
      workspace_root = File.join(temporary, "workspaces", identifier)
      workspace = BenchmarkSupport::PublicWorkloadWorkspace.new(
        directory: workspace_root, workload: workload, checkout: checkout
      ).prepare
      observations = SCENARIOS.flat_map do |scenario|
        options.fetch(:runs).times.map do |index|
          collect_profile(
            identifier, scenario, index + 1, checkout, workspace, workspace_root, options, temporary
          )
        end
      end
      [identifier, observations]
    end
  end

  def collect_profile(identifier, scenario, run, checkout, workspace, workspace_root, options, temporary)
    FileUtils.rm_f(workspace.output)
    stem = "#{identifier}-#{scenario}-#{run}"
    raw_path = File.join(temporary, "#{stem}.dump")
    metadata_path = File.join(temporary, "#{stem}.json")
    command = profile_command(identifier, scenario, checkout, workspace, options)
    metadata = collect_profile_metadata(
      command, workspace, checkout, workspace_root, raw_path, metadata_path, options
    )
    metadata.merge(
      "scenario" => scenario,
      "run" => run,
      "command" => normalize_command(command, checkout: checkout, workspace: workspace_root),
      "raw_profile" => "#{stem}.dump",
      "_temporary_raw_profile" => raw_path
    )
  end

  def collect_profile_metadata(command, workspace, checkout, directory, raw_path, metadata_path, options)
    metadata = execute_profile!(
      command,
      chdir: File.dirname(workspace.grammar),
      raw_path: raw_path,
      metadata_path: metadata_path,
      options: options
    )
    verify_worker_environment!(metadata)
    normalize_profile_metadata(
      metadata,
      checkout: checkout,
      workspace: directory,
      grammar: workspace.grammar,
      output: workspace.output
    )
  end

  def profile_command(identifier, scenario, checkout, workspace, options)
    return profiled_generation_command(workspace) if scenario == "cold_generation"

    generate_unprofiled!(workspace)
    profiled_runtime_command(identifier, checkout, workspace.output, scenario, options)
  end

  def profiled_generation_command(workspace)
    command = BenchmarkSupport::PublicComparisonWorker.command_for(
      "ibex", File.basename(workspace.output), File.basename(workspace.grammar)
    )
    executable = File.join(ROOT, "exe/ibex")
    index = command.index(executable) || raise("formal generator command no longer contains the Ibex executable")
    command.dup.tap { |profiled| profiled[index] = PROFILE_GENERATOR }
  end

  def generate_unprofiled!(workspace)
    command = BenchmarkSupport::PublicComparisonWorker.command_for(
      "ibex", File.basename(workspace.output), File.basename(workspace.grammar)
    )
    stdout, stderr, status = Open3.capture3(*command, chdir: File.dirname(workspace.grammar))
    raise "runtime profile setup generation failed: #{stderr}#{stdout}" unless status.success?
    raise "runtime profile setup did not produce output" unless File.file?(workspace.output)
  end

  def profiled_runtime_command(identifier, checkout, output, scenario, options)
    BenchmarkSupport::ComparisonWorker.ruby_prefix + [
      "-I#{File.join(ROOT, 'lib')}",
      PROFILE_RUNTIME,
      MANIFEST,
      identifier,
      checkout,
      output,
      scenario,
      options.fetch(:warmup).to_s,
      options.fetch(:iterations).to_s
    ]
  end

  def execute_profile!(command, chdir:, raw_path:, metadata_path:, options:)
    profile_environment = {
      "IBEX_PROFILE_RAW" => raw_path,
      "IBEX_PROFILE_METADATA" => metadata_path,
      "IBEX_PROFILE_INTERVAL_USEC" => options.fetch(:interval_usec).to_s,
      "IBEX_PROFILE_TOP_FRAMES" => options.fetch(:top_frames).to_s
    }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    stdout, stderr, status = Open3.capture3(profile_environment, *command, chdir: chdir)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    raise "profile worker failed: #{stderr}#{stdout}" unless status.success?
    raise "profile worker did not produce a raw profile" unless File.file?(raw_path)
    raise "profile worker did not produce metadata" unless File.file?(metadata_path)

    JSON.parse(File.read(metadata_path)).merge("outer_elapsed_ms" => (elapsed * 1_000).round(6))
  end

  def verify_worker_environment!(metadata)
    expected_yjit = BenchmarkSupport::ComparisonWorker.yjit_enabled?
    raise "profile worker YJIT state changed" unless metadata.fetch("yjit_enabled") == expected_yjit

    expected_rubyopt = BenchmarkSupport::ComparisonWorker.rubyopt_metadata.fetch(:sha256)
    raise "profile worker RUBYOPT identity changed" unless metadata["rubyopt_sha256"] == expected_rubyopt
  end

  def verify_profile_equivalence!(profiles)
    profiles.each do |identifier, observations|
      generated = observations.map { |entry| entry.fetch("generated_sha256") }.uniq
      raise "#{identifier} generated output changed between profiles" unless generated.one?

      runtime = observations.reject { |entry| entry.fetch("scenario") == "cold_generation" }
      %w[result_sha256 result_sequence_sha256 result_sequence_length].each do |key|
        values = runtime.map { |entry| entry.fetch(key) }.uniq
        raise "#{identifier} #{key} changed between runtime profiles" unless values.one?
      end
    end
    profiles
  end

  def build_report(options, manifest, checkouts, profiles, final_environment, profile_directory)
    published_profiles = profiles.transform_values do |entries|
      entries.map do |entry|
        entry.except("_temporary_raw_profile").merge(
          "raw_profile" => File.join(File.basename(profile_directory), entry.fetch("raw_profile"))
        )
      end
    end
    BenchmarkSupport::PublicProfileReport.build(
      options: options,
      manifest: manifest,
      checkouts: checkouts,
      profiles: published_profiles,
      environment: final_environment,
      formal_commands: formal_commands(options)
    )
  end

  def formal_commands(options)
    options.fetch(:projects).to_h do |identifier|
      generation = BenchmarkSupport::PublicComparisonWorker.command_for(
        "ibex", "<generated-output>", "<public-grammar>"
      )
      workers = SCENARIOS.to_h do |scenario|
        worker_options = {
          warmup: options.fetch(:warmup),
          iterations: options.fetch(:iterations),
          probe_iterations: 5
        }
        command = PublicPerformanceComparison.worker_command(
          "ibex", scenario, identifier, "<checkout>", worker_options
        )
        [scenario, normalize_command(command, checkout: "<checkout>", workspace: nil)]
      end
      [identifier, {
        generation: normalize_command(generation, checkout: nil, workspace: nil),
        workers: workers
      }]
    end
  end

  def normalize_command(command, checkout:, workspace:)
    command.map do |part|
      normalized = part.gsub(ROOT, "<repository>")
      normalized = normalized.gsub(workspace, "<workspace>") if workspace
      normalized = normalized.gsub(checkout, "<checkout>") if checkout && checkout != "<checkout>"
      normalized
    end
  end

  def normalize_profile_metadata(metadata, checkout:, workspace:, grammar:, output:)
    metadata.merge(
      "top_frames" => metadata.fetch("top_frames").map do |frame|
        frame.merge(
          "file" => normalize_profile_path(
            frame["file"], checkout: checkout, workspace: workspace, grammar: grammar, output: output
          )
        )
      end
    )
  end

  def normalize_profile_path(path, checkout:, workspace:, grammar:, output:)
    return path unless path

    replacements = [
      [output, "<generated-parser>"],
      [grammar, "<public-grammar>"],
      [ROOT, "<repository>"],
      [checkout, "<checkout>"],
      [workspace, "<workspace>"]
    ].flat_map do |source, replacement|
      [source, canonical_profile_path(source)].uniq.map { |candidate| [candidate, replacement] }
    end
    replacements.sort_by { |source, _replacement| -source.length }.reduce(path) do |normalized, (source, replacement)|
      normalized.gsub(source, replacement)
    end
  end

  def canonical_profile_path(path)
    File.realpath(path)
  rescue SystemCallError
    path
  end

  def environment
    status = capture!("git", "status", "--porcelain=v1", "--untracked-files=normal").lines(chomp: true)
    tracked = status.any? { |line| !line.start_with?("??") }
    untracked = status.any? { |line| line.start_with?("??") }
    {
      git_revision: capture!("git", "rev-parse", "HEAD"),
      git_dirty: tracked || untracked,
      git_tracked_dirty: tracked,
      git_untracked_dirty: untracked,
      ruby_engine: RUBY_ENGINE,
      ruby_version: RUBY_VERSION,
      ruby_platform: RUBY_PLATFORM,
      ruby_description: RUBY_DESCRIPTION,
      ruby_executable: RbConfig.ruby,
      host_os: RbConfig::CONFIG.fetch("host_os"),
      host_cpu: RbConfig::CONFIG.fetch("host_cpu"),
      kernel_release: Etc.respond_to?(:uname) ? Etc.uname.fetch(:release) : RbConfig::CONFIG.fetch("host_os"),
      processors: Etc.nprocessors,
      yjit_available: !defined?(RubyVM::YJIT).nil?,
      yjit_enabled: BenchmarkSupport::ComparisonWorker.yjit_enabled?,
      ibex_version: Ibex::VERSION,
      rubyopt: BenchmarkSupport::ComparisonWorker.rubyopt_metadata
    }
  end

  def verify_root!(value, allow_dirty:)
    return value if allow_dirty || !value.fetch(:git_dirty)

    raise "diagnostic profiles require a clean repository root; pass --allow-dirty only for local diagnosis"
  end

  def assert_root_unchanged!(before, after)
    before_identity = before.slice(*IDENTITY_KEYS)
    after_identity = after.slice(*IDENTITY_KEYS)
    assert_unchanged!("repository root", before_identity, after_identity)
  end

  def assert_unchanged!(label, before, after)
    raise "#{label} changed while profiles were collected" unless before == after
  end

  def output_paths(path)
    output = File.expand_path(path, ROOT)
    stem = output.sub(/\.json\z/, "")
    [output, "#{stem}.profiles"]
  end

  def reject_existing_outputs!(output, profile_directory)
    raise "profile output already exists: #{output}" if File.exist?(output)
    raise "raw profile output already exists: #{profile_directory}" if File.exist?(profile_directory)
  end

  def publish(output, profile_directory, report, temporary_profiles)
    FileUtils.mkdir_p(File.dirname(output))
    FileUtils.mkdir_p(profile_directory)
    temporary_profiles.each_value do |entries|
      entries.each do |entry|
        FileUtils.cp(entry.fetch("_temporary_raw_profile"), File.join(profile_directory, entry.fetch("raw_profile")))
      end
    end
    File.write(output, "#{JSON.pretty_generate(report)}\n")
  end

  def validate_report!(report)
    schema = JSONSchemer.schema(JSON.parse(File.read(SCHEMA)))
    errors = schema.validate(JSON.parse(JSON.generate(report))).to_a
    raise "diagnostic profile report violates its schema: #{JSON.generate(errors)}" unless errors.empty?

    report
  end

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command, chdir: ROOT)
    raise "profile metadata command failed: #{stderr}#{stdout}" unless status.success?

    stdout.strip
  end
end
# rubocop:enable Metrics/ModuleLength

PublicPerformanceProfile.run(ARGV) if $PROGRAM_NAME == __FILE__
