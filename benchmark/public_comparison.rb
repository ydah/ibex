#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "json_schemer"
require "open3"
require "time"
require_relative "comparison"
require_relative "support/public_comparison_options"
require_relative "support/public_comparison_worker"
require_relative "support/public_workload_manifest"

module PublicPerformanceComparison
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "benchmark/public_comparison.rb")
  MANIFEST = File.join(ROOT, "benchmark/public_workloads.json")
  SCHEMA = File.join(ROOT, "schema/public-performance-comparison-v1.schema.json")
  THIRD_PARTY_WARNING = "This benchmark executes code from the supplied third-party checkouts. " \
                        "Verify each path and revision."
  DEFAULTS = {
    runs: 10,
    warmup: 50,
    iterations: 250,
    probe_iterations: 5,
    bootstrap_samples: 10_000,
    expected_racc_backend: "native",
    projects: nil,
    checkouts: {},
    allow_dirty: false,
    smoke: false,
    output: nil
  }.freeze

  module_function

  def run(arguments)
    return puts(JSON.generate(run_worker(arguments.drop(1)))) if arguments.first == "--worker"

    options, manifest = parse_options(arguments)
    warn "WARNING: #{THIRD_PARTY_WARNING}"
    checkouts = verify_checkouts(options, manifest)
    observations = collect_observations(options, manifest, checkouts)
    require_relative "support/public_comparison_report"
    report = BenchmarkSupport::PublicComparisonReport.build(options, manifest, checkouts, observations)
    validate_report!(report)
    output = "#{JSON.pretty_generate(report)}\n"
    write_output(options[:output], output) if options[:output]
    puts output
  end

  def parse_options(arguments)
    manifest = BenchmarkSupport::PublicWorkloadManifest.new(MANIFEST)
    options = BenchmarkSupport::PublicComparisonOptions.parse(arguments, manifest, DEFAULTS)
    [options, manifest]
  end

  def verify_checkouts(options, manifest)
    options.fetch(:projects).to_h do |identifier|
      root = options.fetch(:checkouts)[identifier]
      raise OptionParser::MissingArgument, "--checkout #{identifier}=PATH is required" unless root

      [identifier, manifest.verify_checkout(identifier, root, allow_dirty: options.fetch(:allow_dirty))]
    end
  end

  def collect_observations(options, manifest, checkouts)
    options.fetch(:projects).to_h do |identifier|
      workload = manifest.fetch(identifier)
      checkout = checkouts.fetch(identifier).fetch(:root)
      scenarios = BenchmarkSupport::PublicComparisonWorker::SCENARIOS.to_h do |scenario|
        implementations = %w[ibex racc].to_h { |implementation| [implementation, []] }
        options.fetch(:runs).times do |index|
          (index.even? ? %w[ibex racc] : %w[racc ibex]).each do |implementation|
            implementations.fetch(implementation) << worker_observation(
              implementation, scenario, workload, checkout, options
            )
          end
        end
        [scenario, implementations]
      end
      [identifier, scenarios]
    end
  end

  def worker_observation(implementation, scenario, workload, checkout, options)
    command = worker_command(implementation, scenario, workload.fetch("id"), checkout, options)
    stdout, stderr, status = Open3.capture3(*command, chdir: ROOT)
    raise "public comparison worker failed: #{stderr}#{stdout}" unless status.success?

    JSON.parse(stdout)
  end

  def worker_command(implementation, scenario, identifier, checkout, options)
    BenchmarkSupport::ComparisonWorker.ruby_prefix + [
      SCRIPT, "--worker", implementation, scenario, identifier, checkout,
      options.fetch(:warmup).to_s, options.fetch(:iterations).to_s, options.fetch(:probe_iterations).to_s
    ]
  end

  def run_worker(arguments)
    implementation, scenario, identifier, checkout, warmup, iterations, probe_iterations = arguments
    workload = BenchmarkSupport::PublicWorkloadManifest.new(MANIFEST).fetch(identifier)
    BenchmarkSupport::PublicComparisonWorker.new(
      implementation: implementation,
      scenario: scenario,
      workload: workload,
      checkout: checkout,
      warmup: Integer(warmup, 10),
      iterations: Integer(iterations, 10),
      probe_iterations: Integer(probe_iterations, 10)
    ).run
  end

  def validate_report!(report)
    schema = JSONSchemer.schema(JSON.parse(File.read(SCHEMA)))
    errors = schema.validate(JSON.parse(JSON.generate(report))).to_a
    raise "assembled public performance report violates its schema: #{JSON.generate(errors)}" unless errors.empty?

    report
  end

  def write_output(path, output)
    absolute = File.expand_path(path, ROOT)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, output)
  end
end

PublicPerformanceComparison.run(ARGV) if $PROGRAM_NAME == __FILE__
