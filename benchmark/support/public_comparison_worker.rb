# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "tmpdir"
require_relative "comparison_worker"
require_relative "public_workload_driver"
require_relative "public_workload_workspace"

module BenchmarkSupport
  # Executes one isolated public-workload observation without reading generated source.
  class PublicComparisonWorker
    ROOT = File.expand_path("../..", __dir__)
    IMPLEMENTATIONS = %w[ibex racc].freeze
    SCENARIOS = %w[cold_generation warm_runtime_reuse warm_runtime_new_instance].freeze

    def initialize(
      implementation:, scenario:, workload:, checkout:, warmup:, iterations:, probe_iterations:, racc_backend:
    )
      @implementation = implementation
      @scenario = scenario
      @workload = workload
      @checkout = checkout
      @warmup = warmup
      @iterations = iterations
      @probe_iterations = probe_iterations
      @racc_backend = racc_backend
      validate!
    end

    def run
      Dir.mktmpdir("ibex-public-comparison-") do |directory|
        workspace = PublicWorkloadWorkspace.new(
          directory: directory, workload: @workload, checkout: @checkout
        ).prepare
        grammar = workspace.grammar
        output = workspace.output
        generation = generate(grammar, output).merge(execution_metadata)
        return generation if @scenario == "cold_generation"

        runtime(output).merge(generation.except("elapsed_ms"))
      end
    end

    def self.command_for(implementation, output, grammar)
      case implementation
      when "ibex"
        ComparisonWorker.ruby_prefix + [
          "-I#{File.join(ROOT, 'lib')}", File.join(ROOT, "exe/ibex"),
          "--table=compact", "--no-line-convert", "--output-file=#{output}", grammar
        ]
      when "racc"
        ComparisonWorker.ruby_prefix + [
          Gem.bin_path("racc", "racc"), "--no-line-convert", "--output-file=#{output}", grammar
        ]
      else
        raise ArgumentError, "unknown implementation #{implementation.inspect}"
      end
    end

    private

    def validate!
      raise ArgumentError, "unknown implementation" unless IMPLEMENTATIONS.include?(@implementation)
      raise ArgumentError, "unknown scenario" unless SCENARIOS.include?(@scenario)
      raise ArgumentError, "unknown Racc backend" unless RaccRuntime::BACKENDS.include?(@racc_backend)
      raise ArgumentError, "warmup must not be negative" if @warmup.negative?
      raise ArgumentError, "iterations must be positive" unless @iterations.positive?
      raise ArgumentError, "probe iterations must be positive" unless @probe_iterations.positive?
    end

    def generate(grammar, output)
      command = self.class.command_for(@implementation, File.basename(output), File.basename(grammar))
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout, stderr, status = Open3.capture3(*command, chdir: File.dirname(grammar))
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      raise "#{@implementation} generation failed: #{stderr}#{stdout}" unless status.success?
      raise "#{@implementation} generation did not produce output" unless File.file?(output)

      {
        "implementation" => @implementation,
        "scenario" => @scenario,
        "elapsed_ms" => milliseconds(elapsed),
        "generated_bytes" => File.size(output)
      }
    end

    def runtime(output)
      driver = PublicWorkloadDriver.new(
        @workload.fetch("driver"), @checkout, output, @implementation, racc_backend: @racc_backend
      ).load!
      reusable = driver.parser if @scenario == "warm_runtime_reuse"
      @warmup.times { run_workload(driver, reusable) }
      measurement = measure(driver, reusable)
      sequence = Array.new(@probe_iterations) { run_workload(driver, reusable) }
      runtime_report(measurement, sequence)
    end

    def measure(driver, reusable)
      GC.start
      before_allocations = GC.stat(:total_allocated_objects)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = nil
      @iterations.times { result = run_workload(driver, reusable) }
      {
        result: result,
        elapsed: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
        allocations: GC.stat(:total_allocated_objects) - before_allocations
      }
    end

    def run_workload(driver, reusable)
      @workload.fetch("inputs").map do |input|
        parser = reusable || driver.parser
        driver.parse(parser, input)
      end
    end

    def runtime_report(measurement, sequence)
      parses = @iterations * @workload.fetch("inputs").length
      result_json = JSON.generate(measurement.fetch(:result))
      {
        "elapsed_ms_per_parse" => milliseconds(measurement.fetch(:elapsed) / parses),
        "allocated_objects_per_parse" => (measurement.fetch(:allocations).to_f / parses).round(3),
        "result_sha256" => Digest::SHA256.hexdigest(result_json),
        "result_sequence_sha256" => Digest::SHA256.hexdigest(JSON.generate(sequence)),
        "result_sequence_length" => sequence.length,
        "runtime_backend" => runtime_backend
      }
    end

    def runtime_backend
      return "ruby" if @implementation == "ibex"

      RaccRuntime.current_backend
    end

    def execution_metadata
      {
        "yjit_enabled" => ComparisonWorker.yjit_enabled?,
        "rubyopt_sha256" => ComparisonWorker.rubyopt_metadata.fetch(:sha256)
      }
    end

    def milliseconds(seconds)
      (seconds * 1_000).round(6)
    end
  end
end
