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

  def test_embedded_parser_includes_versioned_runtime_event_tracer_and_metadata
    source = <<~GRAMMAR
      class EmbeddedEventTraceParser
      token ITEM
      rule
      start: ITEM
      end
      ---- inner
      def next_token = (@tokens ||= [[:ITEM, 9]]).shift
      ---- footer
      parser = EmbeddedEventTraceParser.new
      tracer = Ibex::Runtime::EventJSONLTracer.attach(parser, io: $stdout)
      puts parser.do_parse
      puts tracer.detach
    GRAMMAR
    generated = generate(source)

    Tempfile.create(["embedded-event-trace", ".rb"]) do |file|
      file.write(generated)
      file.flush
      output, errors, status = Open3.capture3(RbConfig.ruby, "--disable-gems", file.path)
      assert status.success?, errors
      events = output.lines[0...-2].map { |line| JSON.parse(line) }
      start = events.first
      assert_equal "start", start.fetch("event")
      assert_equal Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION, start.dig("data", "table_format_version")
      assert_match(/\Asha256:[0-9a-f]{64}\z/, start.dig("data", "grammar_digest"))
      assert_operator start.dig("data", "state_count"), :>, 0
      assert_equal 1, start.dig("data", "production_count")
      assert_equal %W[9\n true\n], output.lines.last(2)
    end
  end

  def test_embedded_parser_includes_bounded_repair
    source = <<~GRAMMAR
      class EmbeddedRepairParser
      token INT '+'
      rule
      expression: expression '+' INT { result = val[0] + val[2] }
                | INT { result = val[0] }
      end
      ---- inner
      def next_token = (@tokens ||= [[:INT, 1], [:INT, 2]]).shift
      def on_repair(plan) = puts("repair=\#{plan.edits.first.kind}:\#{plan.edits.first.token_name}")
      ---- footer
      parser = EmbeddedRepairParser.new
      parser.repair_policy = Ibex::Runtime::RepairPolicy.new
      puts parser.do_parse
    GRAMMAR
    generated = generate(source)

    Tempfile.create(["embedded-repair", ".rb"]) do |file|
      file.write(generated)
      file.flush
      output, errors, status = Open3.capture3(RbConfig.ruby, "--disable-gems", file.path)
      assert status.success?, errors
      assert_equal "repair=insert:'+'\n3\n", output
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
