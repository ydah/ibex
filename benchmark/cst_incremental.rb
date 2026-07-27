# frozen_string_literal: true

require "json"
require "optparse"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ibex"

module CSTIncrementalBenchmark
  module_function

  def run(argv)
    options = parse_options(argv)
    parser_class, input = build_parser(options.fetch(:terms))
    positions = {
      beginning: input.index(/[0-9]/) || 0,
      middle: input.bytesize / 2,
      end: input.rindex(/[0-9]/) || 0
    }
    positions[:middle] = nearest_digit(input, positions.fetch(:middle))
    measurements = positions.transform_values do |position|
      measure_position(parser_class, input, position, options.fetch(:iterations))
    end
    report = {
      benchmark: "ibex_cst_incremental",
      version: 2,
      ruby_version: RUBY_VERSION,
      ruby_platform: RUBY_PLATFORM,
      seed: options.fetch(:seed),
      terms: options.fetch(:terms),
      iterations: options.fetch(:iterations),
      measurements: measurements
    }
    output = JSON.pretty_generate(report)
    File.write(options.fetch(:output), "#{output}\n") if options[:output]
    puts output
  end

  def parse_options(argv)
    options = { terms: 100, iterations: 100, seed: 20_260_727, output: nil }
    OptionParser.new do |parser|
      parser.on("--terms N", Integer) { |value| options[:terms] = value }
      parser.on("--iterations N", Integer) { |value| options[:iterations] = value }
      parser.on("--seed N", Integer) { |value| options[:seed] = value }
      parser.on("--output PATH") { |value| options[:output] = value }
    end.parse!(argv)
    raise OptionParser::InvalidArgument, "terms must exceed one" unless options.fetch(:terms) > 1
    raise OptionParser::InvalidArgument, "iterations must be positive" unless options.fetch(:iterations).positive?

    options
  end

  def build_parser(terms)
    input = Array.new(terms, "1").join(" + ")
    source = <<~GRAMMAR
      class CSTIncrementalBenchmarkParser
      pragma extended
      pragma cst
      token NUM PLUS
      lexer
        skip /[[:space:]]+/
        NUM /[0-9]+/
        PLUS '+'
      end
      rule
      start: terms
      terms: terms PLUS term
           | term
      term: NUM
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "benchmark-cst-incremental.y").parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    generated = Ibex::Codegen::Ruby.new(automaton).generate
    namespace = Module.new
    namespace.module_eval(generated, "benchmark-cst-incremental.rb")
    [namespace.const_get(:CSTIncrementalBenchmarkParser), input]
  end

  def nearest_digit(input, position)
    position += 1 until position >= input.bytesize || input.getbyte(position)&.between?(48, 57)
    position < input.bytesize ? position : (input.rindex(/[0-9]/) || 0)
  end

  def measure_position(parser_class, original, position, iterations)
    stage_b = measure_incremental(parser_class, original, position, iterations, blender: true)
    stage_a = measure_incremental(parser_class, original, position, iterations, blender: false)
    batch = measure_batch(parser_class, original, position, iterations)
    {
      byte_offset: position,
      stage_b: stage_b,
      stage_a: stage_a,
      batch: batch,
      stage_b_vs_stage_a_speedup: stage_a.fetch(:elapsed_ms) / stage_b.fetch(:elapsed_ms),
      stage_b_vs_batch_speedup: batch.fetch(:elapsed_ms) / stage_b.fetch(:elapsed_ms)
    }
  end

  def measure_incremental(parser_class, original, position, iterations, blender:)
    session = parser_class.incremental_session(
      Ibex::Runtime::CST::SourceText.new(original),
      blender: blender
    )
    current = original.dup
    before_allocations = GC.stat.fetch(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    iterations.times do |index|
      replacement = index.even? ? "2" : "1"
      session.edit([Ibex::Runtime::CST::TextEdit.new(start: position, delete_length: 1, insert_text: replacement)])
      current.setbyte(position, replacement.getbyte(0))
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocations = GC.stat.fetch(:total_allocated_objects) - before_allocations
    relexed = session.last_relex_result
    {
      elapsed_ms: elapsed * 1000.0,
      allocated_objects: allocations,
      relexer_scanned_tokens: relexed&.scanned_count,
      reused_ratio: session.result.reused_ratio,
      reused_descendants: session.last_blender&.reused_descendants
    }
  end

  def measure_batch(parser_class, original, position, iterations)
    current = original.dup
    before_allocations = GC.stat.fetch(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    iterations.times do |index|
      replacement = index.even? ? "2" : "1"
      current.setbyte(position, replacement.getbyte(0))
      parser_class.incremental_session(Ibex::Runtime::CST::SourceText.new(current))
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    {
      elapsed_ms: elapsed * 1000.0,
      allocated_objects: GC.stat.fetch(:total_allocated_objects) - before_allocations
    }
  end
end

CSTIncrementalBenchmark.run(ARGV) if $PROGRAM_NAME == __FILE__
