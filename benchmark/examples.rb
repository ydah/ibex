#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ibex"

module ExamplesBenchmark
  ROOT = File.expand_path("..", __dir__)
  EXAMPLES = {
    calculator: {
      class_path: %i[Examples CalculatorParser],
      input: "10 + 2 * (3 + 4) - 6 / 2"
    },
    json: {
      class_path: %i[Examples JSONParser],
      input: '{"project":"Ibex","versions":[3,3.1,4],"flags":{"pure":true,"native":null}}'
    },
    ini: {
      class_path: %i[Examples INIParser],
      input: "title = parser generator\n[server]\nhost = localhost\nport = 9292\n"
    },
    tiny_language: {
      class_path: %i[Examples TinyLanguageParser],
      input: "base = 2 + 3 * 4;\nanswer = base * 2;\nprint answer;\n"
    }
  }.freeze
  TABLES = %i[plain compact].freeze
  LINE_MAPPING = [true, false].freeze
  DEFAULTS = { generation_iterations: 3, runtime_iterations: 100, json: false }.freeze

  module_function

  def run(argv)
    options = parse_options(argv)
    examples = EXAMPLES.to_h do |name, configuration|
      [name, benchmark_example(name, configuration, options)]
    end
    report = {
      generation_iterations: options.fetch(:generation_iterations),
      runtime_iterations: options.fetch(:runtime_iterations),
      examples: examples
    }
    puts(options.fetch(:json) ? JSON.generate(report) : text_report(report))
  end

  def parse_options(argv)
    options = DEFAULTS.dup
    OptionParser.new do |parser|
      parser.banner = "Usage: ruby benchmark/examples.rb [options]"
      parser.on("--generation-iterations N", Integer, "complete builds measured per variant") do |value|
        options[:generation_iterations] = value
      end
      parser.on("--runtime-iterations N", Integer, "parses measured per variant") do |value|
        options[:runtime_iterations] = value
      end
      parser.on("--json", "emit machine-readable JSON") { options[:json] = true }
    end.parse!(argv)
    raise OptionParser::InvalidArgument, "generation iterations must be positive" unless
      options.fetch(:generation_iterations).positive?
    raise OptionParser::InvalidArgument, "runtime iterations must be positive" unless
      options.fetch(:runtime_iterations).positive?

    options
  end

  def benchmark_example(name, configuration, options)
    path = File.join(ROOT, "examples", "#{name}.y")
    source = File.read(path)
    variants = LINE_MAPPING.product(TABLES).map do |line_mapping, table|
      benchmark_variant(source, path, configuration, table, line_mapping, options)
    end
    { grammar: relative_path(path), variants: variants }
  end

  def benchmark_variant(source, path, configuration, table, line_mapping, options)
    generated, generation_ms = measure_average(options.fetch(:generation_iterations)) do
      generate(source, path, table: table, line_mapping: line_mapping)
    end
    parser_class = evaluate(generated, configuration.fetch(:class_path))
    result, runtime_ms = measure_average(options.fetch(:runtime_iterations)) do
      parser_class.new.parse(configuration.fetch(:input))
    end
    {
      table: table,
      line_mapping: line_mapping,
      generation_ms: generation_ms,
      runtime_ms: runtime_ms,
      output_bytes: generated.bytesize,
      generated_sha256: Digest::SHA256.hexdigest(generated),
      result_sha256: Digest::SHA256.hexdigest(Marshal.dump(result))
    }
  end

  def generate(source, path, table:, line_mapping:)
    ast = Ibex::Frontend::Parser.new(source, file: relative_path(path)).parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    Ibex::Codegen::Ruby.new(automaton, table: table, line_convert: line_mapping).generate
  end

  def evaluate(source, class_path)
    namespace = Module.new
    namespace.module_eval(source, "benchmark-generated.rb")
    class_path.reduce(namespace) { |current, name| current.const_get(name, false) }
  end

  def measure_average(iterations)
    result = nil
    digest = nil
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    iterations.times do
      result = yield
      current_digest = Digest::SHA256.hexdigest(Marshal.dump(result))
      raise "benchmark result changed between identical iterations" if digest && digest != current_digest

      digest = current_digest
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    [result, ((elapsed / iterations) * 1000).round(3)]
  end

  def relative_path(path)
    path.delete_prefix("#{ROOT}/")
  end

  def text_report(report)
    lines = [
      "Ibex real-example generation and runtime benchmark",
      "generation iterations: #{report.fetch(:generation_iterations)}",
      "runtime iterations: #{report.fetch(:runtime_iterations)}"
    ]
    report.fetch(:examples).each do |name, example|
      lines << "#{name} (#{example.fetch(:grammar)}):"
      example.fetch(:variants).each do |variant|
        mapping = variant.fetch(:line_mapping) ? "mapped" : "direct"
        lines << format(
          "  %<table>-7s %<mapping>-6s generation=%<generation>8.3f ms " \
          "runtime=%<runtime>8.3f ms bytes=%<bytes>d",
          table: variant.fetch(:table), mapping: mapping, generation: variant.fetch(:generation_ms),
          runtime: variant.fetch(:runtime_ms), bytes: variant.fetch(:output_bytes)
        )
      end
    end
    lines.join("\n")
  end
end

ExamplesBenchmark.run(ARGV) if $PROGRAM_NAME == __FILE__
