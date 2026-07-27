# frozen_string_literal: true

require "json"
require "optparse"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ibex"
require_relative "support/cst_recovery_benchmark"

module CSTBenchmark
  module_function

  def run(argv)
    options = parse_options(argv)
    output = JSON.pretty_generate(benchmark(options))
    File.write(options.fetch(:output), "#{output}\n") if options[:output]
    puts output
  end

  def benchmark(options)
    source = grammar_source(options.fetch(:rules), cst: true)
    plain_source = grammar_source(options.fetch(:rules), cst: false)
    input = Array.new(options.fetch(:rules), "1").join(" + ")
    cst_parser = build_parser(source)
    plain_parser = build_parser(plain_source)
    cst = measure(cst_parser, input, options.fetch(:iterations))
    plain = measure(plain_parser, input, options.fetch(:iterations))
    recovery = CSTRecoveryBenchmark.measure(options.fetch(:iterations))
    {
      benchmark: "ibex_cst_baseline",
      version: 3,
      ruby_version: RUBY_VERSION,
      ruby_platform: RUBY_PLATFORM,
      seed: options.fetch(:seed),
      rules: options.fetch(:rules),
      iterations: options.fetch(:iterations),
      measurements: { plain: plain, cst: cst },
      cst_overhead_ratio: cst.fetch(:elapsed_ms) / plain.fetch(:elapsed_ms),
      green_identity: green_identity(cst_parser, input),
      recovery: recovery
    }
  end

  def parse_options(argv)
    options = { rules: 25, iterations: 20, seed: 12_345, output: nil }
    OptionParser.new do |parser|
      parser.on("--rules N", Integer) { |value| options[:rules] = value }
      parser.on("--iterations N", Integer) { |value| options[:iterations] = value }
      parser.on("--seed N", Integer) { |value| options[:seed] = value }
      parser.on("--output PATH") { |value| options[:output] = value }
    end.parse!(argv)
    raise OptionParser::InvalidArgument, "rules must be positive" unless options.fetch(:rules).positive?
    raise OptionParser::InvalidArgument, "iterations must be positive" unless options.fetch(:iterations).positive?

    options
  end

  def grammar_source(rules, cst:)
    rhs = Array.new(rules, "NUM").join(" PLUS ")
    pragmas = ["pragma extended"]
    pragmas << "pragma cst" if cst
    <<~GRAMMAR
      class CSTBenchmarkParser
      #{pragmas.join("\n")}
      token NUM PLUS
      lexer
        skip /[[:space:]]+/
        NUM /[0-9]+/ { lexeme.to_i }
        PLUS '+'
      end
      rule
      start: #{rhs}
      end
    GRAMMAR
  end

  def build_parser(source)
    ast = Ibex::Frontend::Parser.new(source, file: "benchmark-cst.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    generated = Ibex::Codegen::Ruby.new(automaton).generate
    namespace = Module.new
    namespace.module_eval(generated, "benchmark-cst.rb")
    namespace.const_get(grammar.class_name)
  end

  def measure(parser_class, input, iterations, suppress_legacy_warning: false)
    parse_once(parser_class, input, suppress_legacy_warning: suppress_legacy_warning)
    before_allocations = GC.stat.fetch(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    iterations.times do
      parse_once(parser_class, input, suppress_legacy_warning: suppress_legacy_warning)
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    after_allocations = GC.stat.fetch(:total_allocated_objects)
    {
      elapsed_ms: elapsed * 1000.0,
      allocated_objects: after_allocations - before_allocations
    }
  end

  def parse_once(parser_class, input, suppress_legacy_warning:)
    parser = parser_class.new
    parser.instance_variable_set(:@legacy_cst_warning_emitted, true) if suppress_legacy_warning
    parser.parse(input)
  end

  def green_identity(parser_class, input)
    parser = parser_class.new
    parser.parse(input)
    root = parser.syntax_root
    raise "CST benchmark parser did not produce a syntax root" unless root

    occurrences = []
    stack = [root.green]
    until stack.empty?
      green = stack.pop
      occurrences << green
      stack.concat(green.children.reverse) if green.is_a?(Ibex::Runtime::CST::GreenNode)
    end
    unique_objects = occurrences.map(&:object_id).uniq.length
    {
      occurrences: occurrences.length,
      unique_objects: unique_objects,
      identity_reuse_ratio: 1.0 - unique_objects.fdiv(occurrences.length)
    }
  end
end

CSTBenchmark.run(ARGV) if $PROGRAM_NAME == __FILE__
