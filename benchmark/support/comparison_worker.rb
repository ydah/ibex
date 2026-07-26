# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rbconfig"
require "rubygems"
require "tmpdir"

module BenchmarkSupport
  # Runs one implementation/scenario observation without inspecting generated source.
  class ComparisonWorker
    ROOT = File.expand_path("../..", __dir__)
    GRAMMAR = File.join(ROOT, "benchmark/grammars/representative.y")
    INPUT = File.join(ROOT, "benchmark/grammars/representative.input")
    CLASS_NAME = :BenchmarkRepresentativeParser
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

    def initialize(implementation:, scenario:, warmup:, runtime_iterations:, workload_seed:)
      @implementation = implementation
      @scenario = scenario
      @warmup = warmup
      @runtime_iterations = runtime_iterations
      @workload_seed = workload_seed
      validate!
    end

    def run
      Dir.mktmpdir("ibex-performance-comparison-") do |directory|
        output = File.join(directory, "generated_parser.rb")
        grammar = File.join(directory, "representative.y")
        File.write(grammar, self.class.comparison_grammar_source)
        generation = generate(output, grammar)
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
      [RbConfig.ruby, *("--yjit" if yjit_enabled?)]
    end

    def self.yjit_enabled?
      return false unless defined?(RubyVM::YJIT)

      RubyVM::YJIT.enabled?
    end

    private

    def validate!
      unless IMPLEMENTATIONS.include?(@implementation)
        raise ArgumentError, "unknown implementation #{@implementation.inspect}"
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
      $LOAD_PATH.unshift(File.join(ROOT, "lib")) unless $LOAD_PATH.include?(File.join(ROOT, "lib"))
      load output
      parser_class = Object.const_get(CLASS_NAME, false)
      input = "#{File.read(INPUT)}\nlet benchmark_seed: Number = #{@workload_seed};\n"
      driver, lifecycle = RUNTIME_SCENARIOS.fetch(@scenario)
      payload = driver == :tokens ? parser_class.new.tokenize(input) : input
      parser = parser_class.new if lifecycle == :reuse
      @warmup.times { invoke(parser_class, parser, driver, payload) }
      GC.start
      before_allocations = GC.stat(:total_allocated_objects)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = nil
      @runtime_iterations.times { result = invoke(parser_class, parser, driver, payload) }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      allocations = GC.stat(:total_allocated_objects) - before_allocations
      {
        "elapsed_ms_per_parse" => milliseconds(elapsed / @runtime_iterations),
        "allocated_objects_per_parse" => (allocations.to_f / @runtime_iterations).round(3),
        "result_sha256" => Digest::SHA256.hexdigest(JSON.generate(result)),
        "behavior_sha256" => behavior_digest(result),
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

    def runtime_backend
      return "ruby" if @implementation == "ibex"

      native = $LOADED_FEATURES.any? { |path| File.basename(path).match?(/\Acparse\.(?:bundle|dll|so)\z/) }
      native ? "native" : "ruby"
    end

    def milliseconds(seconds)
      (seconds * 1_000).round(6)
    end
  end
end
