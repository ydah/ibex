#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "etc"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "rbconfig"
require "time"
require_relative "support/comparison_statistics"
require_relative "support/comparison_worker"

# rubocop:disable Metrics/ModuleLength -- this executable owns one complete comparison protocol.
module PerformanceComparison
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "benchmark/comparison.rb")
  GRAMMAR = File.join(ROOT, "benchmark/grammars/representative.y")
  INPUT = File.join(ROOT, "benchmark/grammars/representative.input")
  IMPLEMENTATIONS = %w[ibex racc].freeze
  SCENARIOS = %w[
    cold_generation
    warm_runtime_end_to_end_reuse
    warm_runtime_end_to_end_new_instance
    warm_runtime_tokens_reuse
    warm_runtime_tokens_new_instance
  ].freeze
  DEFAULTS = {
    runs: 10,
    warmup: 50,
    runtime_iterations: 250,
    workload_seed: 12_345,
    bootstrap_samples: 10_000,
    output: nil
  }.freeze

  module_function

  def run(arguments)
    return puts(JSON.generate(run_worker(arguments.drop(1)))) if arguments.first == "--worker"

    options = parse_options(arguments)
    report = report_document(options, collect_observations(options))
    output = "#{JSON.pretty_generate(report)}\n"
    write_output(options[:output], output) if options[:output]
    puts output
  end

  def parse_options(arguments)
    options = DEFAULTS.dup
    OptionParser.new do |parser|
      parser.banner = "Usage: benchmark/comparison.rb [options]"
      parser.on("--runs N", Integer, "isolated processes per implementation and scenario") do |value|
        options[:runs] = value
      end
      parser.on("--warmup N", Integer, "warmup parses in each runtime process") { |value| options[:warmup] = value }
      parser.on("--runtime-iterations N", Integer, "measured parses in each runtime process") do |value|
        options[:runtime_iterations] = value
      end
      parser.on("--workload-seed N", Integer, "deterministic input suffix seed") do |value|
        options[:workload_seed] = value
      end
      parser.on("--bootstrap-samples N", Integer, "deterministic bootstrap resamples") do |value|
        options[:bootstrap_samples] = value
      end
      parser.on("--output PATH", "write the JSON report") { |value| options[:output] = value }
    end.parse!(arguments)
    validate_options!(options)
    options
  end

  def validate_options!(options)
    raise OptionParser::InvalidArgument, "runs must be positive" unless options.fetch(:runs).positive?
    raise OptionParser::InvalidArgument, "at least ten isolated runs are required" if options.fetch(:runs) < 10
    raise OptionParser::InvalidArgument, "warmup must not be negative" if options.fetch(:warmup).negative?
    unless options.fetch(:runtime_iterations).positive?
      raise OptionParser::InvalidArgument, "runtime iterations must be positive"
    end
    return if options.fetch(:bootstrap_samples) >= 1_000

    raise OptionParser::InvalidArgument, "bootstrap samples must be at least 1000"
  end

  def collect_observations(options)
    SCENARIOS.to_h do |scenario|
      observations = IMPLEMENTATIONS.to_h { |implementation| [implementation, []] }
      options.fetch(:runs).times do |index|
        order = index.even? ? IMPLEMENTATIONS : IMPLEMENTATIONS.reverse
        order.each do |implementation|
          observations.fetch(implementation) << worker_observation(implementation, scenario, options)
        end
      end
      [scenario, observations]
    end
  end

  def worker_observation(implementation, scenario, options)
    command = worker_command(implementation, scenario, options)
    stdout, stderr, status = Open3.capture3(*command, chdir: ROOT)
    raise "comparison worker failed: #{stderr}#{stdout}" unless status.success?

    JSON.parse(stdout)
  end

  def worker_command(implementation, scenario, options)
    BenchmarkSupport::ComparisonWorker.ruby_prefix + [
      SCRIPT,
      "--worker",
      implementation,
      scenario,
      options.fetch(:warmup).to_s,
      options.fetch(:runtime_iterations).to_s,
      options.fetch(:workload_seed).to_s
    ]
  end

  def run_worker(arguments)
    implementation, scenario, warmup, runtime_iterations, workload_seed = arguments
    BenchmarkSupport::ComparisonWorker.new(
      implementation: implementation,
      scenario: scenario,
      warmup: Integer(warmup, 10),
      runtime_iterations: Integer(runtime_iterations, 10),
      workload_seed: Integer(workload_seed, 10)
    ).run
  end

  def report_document(options, observations)
    assert_cross_scenario_behavior!(observations)
    {
      artifact: "ibex_racc_performance_comparison",
      schema_version: 1,
      recorded_at: Time.now.utc.iso8601,
      environment: environment,
      configuration: configuration(options),
      workload: workload(options),
      commands: commands(options),
      scenarios: SCENARIOS.to_h do |scenario|
        [scenario.to_sym, summarize_scenario(scenario, observations.fetch(scenario), options)]
      end
    }
  end

  def summarize_scenario(scenario, observations, options)
    summaries = observations.transform_values do |entries|
      scenario == "cold_generation" ? summarize_generation(entries) : summarize_runtime(entries)
    end
    comparison = if scenario == "cold_generation"
                   generation_comparison(scenario, summaries, options)
                 else
                   runtime_comparison(scenario, summaries, options)
                 end
    { implementations: summaries.transform_keys(&:to_sym), comparison: comparison }
  end

  def summarize_generation(entries)
    assert_stable!(entries, %w[implementation scenario generated_bytes])
    elapsed = entries.map { |entry| entry.fetch("elapsed_ms") }
    {
      observations: { elapsed_ms: elapsed },
      statistics: { elapsed_ms: BenchmarkSupport::ComparisonStatistics.describe(elapsed) },
      generated: generated_summary(entries)
    }
  end

  def summarize_runtime(entries)
    stable = %w[implementation scenario generated_bytes result_sha256 behavior_sha256 runtime_backend]
    assert_stable!(entries, stable)
    elapsed = entries.map { |entry| entry.fetch("elapsed_ms_per_parse") }
    allocations = entries.map { |entry| entry.fetch("allocated_objects_per_parse") }
    reference = entries.first
    {
      observations: {
        elapsed_ms_per_parse: elapsed,
        allocated_objects_per_parse: allocations
      },
      statistics: {
        elapsed_ms_per_parse: BenchmarkSupport::ComparisonStatistics.describe(elapsed),
        allocated_objects_per_parse: BenchmarkSupport::ComparisonStatistics.describe(allocations)
      },
      generated: generated_summary(entries),
      result_sha256: reference.fetch("result_sha256"),
      behavior_sha256: reference.fetch("behavior_sha256"),
      runtime_backend: reference.fetch("runtime_backend")
    }
  end

  def generation_comparison(scenario, summaries, options)
    {
      elapsed_ms: compare_metric(scenario, "elapsed", summaries, %i[observations elapsed_ms], options),
      generated_bytes: size_comparison(summaries)
    }
  end

  def runtime_comparison(scenario, summaries, options)
    {
      elapsed_ms_per_parse: compare_metric(
        scenario, "elapsed", summaries, %i[observations elapsed_ms_per_parse], options
      ),
      allocated_objects_per_parse: compare_metric(
        scenario, "allocations", summaries, %i[observations allocated_objects_per_parse], options
      ),
      generated_bytes: size_comparison(summaries),
      result_equivalent: unique_summary_values(summaries, :result_sha256).one?,
      behavior_equivalent: unique_summary_values(summaries, :behavior_sha256).one?
    }
  end

  def compare_metric(scenario, metric, summaries, path, options)
    seed = statistic_seed(options.fetch(:workload_seed), scenario, metric)
    ibex = path.reduce(summaries.fetch("ibex")) { |value, key| value.fetch(key) }
    racc = path.reduce(summaries.fetch("racc")) { |value, key| value.fetch(key) }
    BenchmarkSupport::ComparisonStatistics.compare(
      ibex,
      racc,
      seed: seed,
      samples: options.fetch(:bootstrap_samples)
    )
  end

  def size_comparison(summaries)
    ibex = summaries.dig("ibex", :generated, :bytes)
    racc = summaries.dig("racc", :generated, :bytes)
    {
      ibex_bytes: ibex,
      racc_bytes: racc,
      ibex_to_racc_ratio: (ibex.to_f / racc).round(6)
    }
  end

  def unique_summary_values(summaries, key)
    summaries.values.map { |summary| summary.fetch(key) }.uniq
  end

  def generated_summary(entries)
    reference = entries.first
    { bytes: reference.fetch("generated_bytes") }
  end

  def assert_stable!(entries, keys)
    keys.each do |key|
      values = entries.map { |entry| entry.fetch(key) }.uniq
      raise "#{key} changed between isolated runs" unless values.one?
    end
  end

  def assert_cross_scenario_behavior!(observations)
    runtime = observations.except("cold_generation").values.flat_map do |implementations|
      implementations.values.flatten(1)
    end
    %w[result_sha256 behavior_sha256].each do |key|
      values = runtime.map { |entry| entry.fetch(key) }.uniq
      raise "#{key} differs across implementations or scenarios" unless values.one?
    end
  end

  def statistic_seed(workload_seed, scenario, metric)
    suffix = Digest::SHA256.hexdigest("#{scenario}:#{metric}").slice(0, 8).to_i(16)
    workload_seed ^ suffix
  end

  def configuration(options)
    {
      runs: options.fetch(:runs),
      warmup: options.fetch(:warmup),
      runtime_iterations: options.fetch(:runtime_iterations),
      workload_seed: options.fetch(:workload_seed),
      bootstrap_samples: options.fetch(:bootstrap_samples),
      confidence_level: BenchmarkSupport::ComparisonStatistics::CONFIDENCE_LEVEL,
      process_order: "alternating_per_run"
    }
  end

  def workload(options)
    input = File.read(INPUT)
    effective_input = "#{input}\nlet benchmark_seed: Number = #{options.fetch(:workload_seed)};\n"
    comparison_grammar = BenchmarkSupport::ComparisonWorker.comparison_grammar_source
    {
      grammar: "benchmark/grammars/representative.y",
      input: "benchmark/grammars/representative.input",
      source_grammar_sha256: Digest::SHA256.file(GRAMMAR).hexdigest,
      comparison_grammar_sha256: Digest::SHA256.hexdigest(comparison_grammar),
      grammar_adaptation: "normalize_eof_and_add_pretokenized_driver",
      input_sha256: Digest::SHA256.hexdigest(input),
      effective_input_sha256: Digest::SHA256.hexdigest(effective_input),
      parser_class: "BenchmarkRepresentativeParser",
      runtime_dimensions: %w[lexer_inclusive pretokenized],
      parser_lifecycles: %w[reuse new_instance]
    }
  end

  def commands(options)
    worker = worker_command("<implementation>", "<scenario>", options).map { |part| normalized_path(part) }
    {
      worker: worker,
      generation: IMPLEMENTATIONS.to_h do |implementation|
        [implementation.to_sym, BenchmarkSupport::ComparisonWorker.command_template(implementation).map do |part|
          normalized_path(part)
        end]
      end
    }
  end

  def environment
    {
      git_revision: capture!("git", "rev-parse", "HEAD"),
      git_dirty: !capture!("git", "status", "--porcelain", "--untracked-files=no").empty?,
      ruby_engine: RUBY_ENGINE,
      ruby_version: RUBY_VERSION,
      ruby_platform: RUBY_PLATFORM,
      ruby_description: RUBY_DESCRIPTION,
      ruby_executable: RbConfig.ruby,
      host_os: RbConfig::CONFIG.fetch("host_os"),
      host_cpu: RbConfig::CONFIG.fetch("host_cpu"),
      processors: Etc.nprocessors,
      yjit_available: !defined?(RubyVM::YJIT).nil?,
      yjit_enabled: BenchmarkSupport::ComparisonWorker.yjit_enabled?,
      ibex_version: capture!(
        *BenchmarkSupport::ComparisonWorker.ruby_prefix,
        "-I#{File.join(ROOT, 'lib')}", "-ribex/version", "-e", "print Ibex::VERSION"
      ),
      racc_version: capture!(*BenchmarkSupport::ComparisonWorker.ruby_prefix, "-rracc/parser", "-e", "print Racc::VERSION"),
      racc_executable: Gem.bin_path("racc", "racc")
    }
  end

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command, chdir: ROOT)
    raise "metadata command failed: #{stderr}#{stdout}" unless status.success?

    stdout.strip
  end

  def normalized_path(value)
    value.gsub(ROOT, "<repository>")
  end

  def write_output(path, output)
    absolute = File.expand_path(path, ROOT)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, output)
  end
end
# rubocop:enable Metrics/ModuleLength

PerformanceComparison.run(ARGV) if $PROGRAM_NAME == __FILE__
