# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rbconfig"
require "rubygems"
require "tmpdir"
require_relative "racc_runtime"
require_relative "rubyopt_metadata"

module BenchmarkSupport
  # Runs one implementation/scenario observation without inspecting generated source.
  class ComparisonWorker
    ROOT = File.expand_path("../..", __dir__)
    GRAMMAR = File.join(ROOT, "benchmark/grammars/representative.y")
    INPUT = File.join(ROOT, "benchmark/grammars/representative.input")
    CLASS_NAME = :BenchmarkRepresentativeParser
    MAX_BEHAVIOR_PROBE_ITERATIONS = 100
    IMPLEMENTATIONS = %w[ibex racc].freeze
    TOKEN_DRIVER_METHODS = <<~RUBY
      def tokenize(source)
        @scanner = StringScanner.new(source)
        tokens = []
        loop do
          token = next_token
          tokens << token
          break unless token[0]
        end
        tokens.freeze
      end

      def parse_tokens(tokens)
        @benchmark_tokens = tokens.each
        do_parse
      ensure
        @benchmark_tokens = nil
      end

    RUBY
    RUNTIME_SCENARIOS = {
      "warm_runtime_end_to_end_reuse" => %i[source reuse],
      "warm_runtime_end_to_end_new_instance" => %i[source new_instance],
      "warm_runtime_tokens_reuse" => %i[tokens reuse],
      "warm_runtime_tokens_new_instance" => %i[tokens new_instance]
    }.freeze

    def initialize(
      implementation:,
      scenario:,
      warmup:,
      runtime_iterations:,
      workload_seed:,
      behavior_probe_iterations:,
      racc_backend:
    )
      @implementation = implementation
      @scenario = scenario
      @warmup = warmup
      @runtime_iterations = runtime_iterations
      @workload_seed = workload_seed
      @behavior_probe_iterations = behavior_probe_iterations
      @racc_backend = racc_backend
      validate!
    end

    def run
      Dir.mktmpdir("ibex-performance-comparison-") do |directory|
        output = File.join(directory, "generated_parser.rb")
        grammar = File.join(directory, "representative.y")
        File.write(grammar, self.class.comparison_grammar_source)
        generation = generate(output, grammar).merge(execution_metadata)
        return generation if @scenario == "cold_generation"

        runtime(output).merge(generation.except("elapsed_ms"))
      end
    end

    def self.command_template(implementation)
      output = "<generated-output>"
      command_for(implementation, output, "<comparison-grammar>")
    end

    def self.command_for(implementation, output, grammar)
      case implementation
      when "ibex"
        ruby_prefix + [
          "-I#{File.join(ROOT, 'lib')}",
          File.join(ROOT, "exe/ibex"),
          "--table=compact",
          "--no-line-convert",
          "--output-file=#{output}",
          grammar
        ]
      when "racc"
        ruby_prefix + [Gem.bin_path("racc", "racc"), "--no-line-convert", "--output-file=#{output}", grammar]
      else
        raise ArgumentError, "unknown implementation #{implementation.inspect}"
      end
    end

    def self.comparison_grammar_source
      source = File.read(GRAMMAR)
      next_token_marker = "def next_token\n"
      eof_marker = "  return false if @scanner.eos?\n"
      unless source.scan(next_token_marker).one? && source.scan(eof_marker).one?
        raise "representative grammar adapter boundary changed"
      end

      with_driver = source.sub(
        next_token_marker,
        "#{TOKEN_DRIVER_METHODS}def next_token\n  return @benchmark_tokens.next if @benchmark_tokens\n\n"
      )
      with_driver.sub(eof_marker, "  return [false, false] if @scanner.eos?\n")
    end

    def self.ruby_prefix
      prefix = [RbConfig.ruby]
      return prefix unless defined?(RubyVM::YJIT)

      prefix << (yjit_enabled? ? "--yjit" : "--disable-yjit")
    end

    def self.yjit_enabled?
      return false unless defined?(RubyVM::YJIT)

      RubyVM::YJIT.enabled?
    end

    def self.rubyopt_metadata(raw = ENV.fetch("RUBYOPT", nil))
      RubyoptMetadata.build(raw)
    end

    def self.result_sequence_digest(results)
      Digest::SHA256.hexdigest(JSON.generate(results))
    end

    private

    def validate!
      unless IMPLEMENTATIONS.include?(@implementation)
        raise ArgumentError, "unknown implementation #{@implementation.inspect}"
      end
      raise ArgumentError, "unknown Racc backend #{@racc_backend.inspect}" unless
        RaccRuntime::BACKENDS.include?(@racc_backend)
      raise ArgumentError, "warmup must not be negative" if @warmup.negative?
      raise ArgumentError, "runtime iterations must be positive" unless @runtime_iterations.positive?
      raise ArgumentError, "workload seed must not be negative" if @workload_seed.negative?
      unless (1..MAX_BEHAVIOR_PROBE_ITERATIONS).cover?(@behavior_probe_iterations)
        raise ArgumentError, "behavior probe iterations must be between 1 and #{MAX_BEHAVIOR_PROBE_ITERATIONS}"
      end
      return if @scenario == "cold_generation" || RUNTIME_SCENARIOS.key?(@scenario)

      raise ArgumentError, "unknown comparison scenario #{@scenario.inspect}"
    end

    def generate(output, grammar)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      command = self.class.command_for(@implementation, File.basename(output), File.basename(grammar))
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
      parser_class, parser, driver, payload = runtime_context(output)
      @warmup.times { invoke(parser_class, parser, driver, payload) }
      measurement = measure_runtime(parser_class, parser, driver, payload)
      result_sequence = Array.new(@behavior_probe_iterations) do
        invoke(parser_class, parser, driver, payload)
      end
      runtime_report(measurement, result_sequence)
    end

    def runtime_context(output)
      $LOAD_PATH.unshift(File.join(ROOT, "lib")) unless $LOAD_PATH.include?(File.join(ROOT, "lib"))
      RaccRuntime.load!(@racc_backend) if @implementation == "racc"
      load output
      parser_class = Object.const_get(CLASS_NAME, false)
      input = "#{File.read(INPUT)}\nlet benchmark_seed: Number = #{@workload_seed};\n"
      driver, lifecycle = RUNTIME_SCENARIOS.fetch(@scenario)
      payload = driver == :tokens ? parser_class.new.tokenize(input) : input
      parser = parser_class.new if lifecycle == :reuse
      [parser_class, parser, driver, payload]
    end

    def measure_runtime(parser_class, parser, driver, payload)
      GC.start
      before_allocations = GC.stat(:total_allocated_objects)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = nil
      @runtime_iterations.times { result = invoke(parser_class, parser, driver, payload) }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      allocations = GC.stat(:total_allocated_objects) - before_allocations
      { result: result, elapsed: elapsed, allocations: allocations }
    end

    def runtime_report(measurement, result_sequence)
      result = measurement.fetch(:result)
      {
        "elapsed_ms_per_parse" => milliseconds(measurement.fetch(:elapsed) / @runtime_iterations),
        "allocated_objects_per_parse" => (measurement.fetch(:allocations).to_f / @runtime_iterations).round(3),
        "result_sha256" => Digest::SHA256.hexdigest(JSON.generate(result)),
        "behavior_sha256" => behavior_digest(result),
        "result_sequence_sha256" => self.class.result_sequence_digest(result_sequence),
        "result_sequence_length" => result_sequence.length,
        "runtime_backend" => runtime_backend
      }
    end

    def invoke(parser_class, reusable_parser, driver, payload)
      parser = reusable_parser || parser_class.new
      driver == :tokens ? parser.parse_tokens(payload) : parser.parse(payload)
    end

    def behavior_digest(result)
      Digest::SHA256.hexdigest(JSON.generate(status: "returned", result_class: result.class.name, result: result))
    end

    def execution_metadata
      rubyopt = self.class.rubyopt_metadata
      {
        "yjit_enabled" => self.class.yjit_enabled?,
        "rubyopt_sha256" => rubyopt.fetch(:sha256)
      }
    end

    def runtime_backend
      return "ruby" if @implementation == "ibex"

      RaccRuntime.current_backend
    end

    def milliseconds(seconds)
      (seconds * 1_000).round(6)
    end
  end
end
