# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "rbconfig"
require "tempfile"

class EmbeddedTracerCodegenTest < Minitest::Test
  def test_embedded_parser_includes_the_jsonl_tracer
    source = <<~GRAMMAR
      class EmbeddedTraceParser
      token ITEM
      rule
      start: ITEM
      end
      ---- inner
      def next_token = (@tokens ||= [[:ITEM, 7]]).shift
      ---- footer
      parser = EmbeddedTraceParser.new
      Ibex::Runtime::JSONLTracer.attach(parser, io: $stdout)
      puts parser.do_parse
    GRAMMAR
    generated = generate(source)

    Tempfile.create(["embedded-trace", ".rb"]) do |file|
      file.write(generated)
      file.flush
      output, errors, status = Open3.capture3(RbConfig.ruby, "--disable-gems", file.path)
      assert status.success?, errors
      events = output.lines[0...-1].map { |line| JSON.parse(line) }
      assert_equal "7\n", output.lines.last
      assert_equal "shift", events.first.fetch("event")
      assert_equal "ITEM", events.first.fetch("token")
    end
  end

  private

  def generate(source)
    ast = Ibex::Frontend::Parser.new(source, file: "embedded-trace.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    Ibex::Codegen::Ruby.new(automaton, embedded: true).generate
  end
end
