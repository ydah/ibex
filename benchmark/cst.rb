# frozen_string_literal: true

require "json"
require "optparse"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ibex"

module CSTBenchmark
  module_function

  def run(argv)
    options = parse_options(argv)
    source = grammar_source(options.fetch(:rules), cst: true)
    plain_source = grammar_source(options.fetch(:rules), cst: false)
    input = Array.new(options.fetch(:rules), "1").join(" + ")
    cst_parser = build_parser(source)
    plain_parser = build_parser(plain_source)
    cst = measure(cst_parser, input, options.fetch(:iterations))
    plain = measure(plain_parser, input, options.fetch(:iterations))
    report = {
      benchmark: "ibex_cst_baseline",
      version: 1,
      seed: options.fetch(:seed),
      rules: options.fetch(:rules),
      iterations: options.fetch(:iterations),
      measurements: { plain: plain, cst: cst },
      cst_overhead_ratio: cst.fetch(:elapsed_ms) / plain.fetch(:elapsed_ms)
    }
    output = JSON.pretty_generate(report)
    File.write(options.fetch(:output), "#{output}\n") if options[:output]
    puts output
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
    namespace.const_get(:CSTBenchmarkParser)
  end

  def measure(parser_class, input, iterations)
    parser_class.new.parse(input)
    before_allocations = GC.stat.fetch(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    iterations.times { parser_class.new.parse(input) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    after_allocations = GC.stat.fetch(:total_allocated_objects)
    {
      elapsed_ms: elapsed * 1000.0,
      allocated_objects: after_allocations - before_allocations
    }
  end
end

CSTBenchmark.run(ARGV) if $PROGRAM_NAME == __FILE__
