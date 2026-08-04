# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ibex"

module ErrorUXSnapshot
  ROOT = File.expand_path("..", __dir__)
  IBEX_GRAMMAR = File.join(ROOT, "examples/json.y")
  RACC_GRAMMAR = File.join(ROOT, "test/fixtures/error_ux/json_racc.y")
  SNAPSHOT = File.join(ROOT, "test/fixtures/error_ux/json-errors-v1.json")
  CASES = [
    ["EUX-01", '{"a":,}', true, "supplies one missing value after the member colon"],
    ["EUX-02", '{"a" 1}', true, "inserts the missing member colon"],
    ["EUX-03", '{"a":1,}', false, "invents another member instead of removing the trailing comma"],
    ["EUX-04", "[1,]", false, "invents another element instead of removing the trailing comma"],
    ["EUX-05", "[1 2]", true, "inserts the missing element comma"],
    ["EUX-06", '{"a":[true false]}', true, "inserts the missing element comma"],
    ["EUX-07", '{"a":null "b":2}', true, "inserts the missing member comma"],
    ["EUX-08", "{]", true, "replaces the mismatched closing bracket with a brace"],
    ["EUX-09", "[}", true, "replaces the mismatched closing brace with a bracket"],
    ["EUX-10", "true false", true, "removes the extra top-level value"]
  ].freeze

  module_function

  def build
    ibex_parser = build_ibex_parser
    racc_parser, racc_version = build_racc_parser
    {
      "schema_version" => 1,
      "ibex_grammar" => "examples/json.y",
      "racc_grammar" => "test/fixtures/error_ux/json_racc.y",
      "racc_version" => racc_version,
      "sp4" => {
        "useful_repairs" => CASES.count { |entry| entry.fetch(2) },
        "total_cases" => CASES.length,
        "decision" => "go"
      },
      "cases" => CASES.map do |id, input, useful, assessment|
        {
          "id" => id,
          "input" => input,
          "ibex" => observe_ibex(ibex_parser, input),
          "racc" => observe_racc(racc_parser, input),
          "repair" => observe_repair(ibex_parser, input).merge(
            "useful" => useful,
            "assessment" => assessment
          )
        }
      end
    }
  end

  def render
    "#{JSON.pretty_generate(build)}\n"
  end

  def verify?
    expected = File.binread(SNAPSHOT)
    actual = render
    return true if expected == actual

    warn "#{SNAPSHOT} is stale; run tool/error_ux_snapshot.rb --write after reviewing the diagnostic changes"
    false
  end

  def write
    File.binwrite(SNAPSHOT, render)
  end

  def build_ibex_parser
    source = File.binread(IBEX_GRAMMAR)
    ast = Ibex::Frontend::Parser.new(source, file: IBEX_GRAMMAR).parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    generated = Ibex::Codegen::Ruby.new(automaton, table: :compact, line_convert: false).generate
    namespace = Module.new
    namespace.module_eval(generated, "(generated-json-parser)")
    namespace.const_get(:Examples, false).const_get(:JSONParser, false)
  end

  def build_racc_parser
    command = ENV.fetch("RACC", "racc")
    version, version_status = Open3.capture2(command, "--version")
    raise "racc --version failed" unless version_status.success?

    parser = Dir.mktmpdir("ibex-error-ux-racc") do |directory|
      output = File.join(directory, "json_racc_parser.rb")
      system(command, "-o", output, RACC_GRAMMAR, out: File::NULL, err: File::NULL) ||
        raise("racc compilation failed")
      namespace = Module.new
      namespace.module_eval(File.binread(output), output)
      namespace.const_get(:ErrorUXJSONRaccParser, false)
    end
    [parser, version.strip]
  end

  def observe_ibex(parser_class, input)
    parser_class.new.parse(input)
    { "status" => "accepted" }
  rescue Ibex::ParseError => e
    location = e.location
    line = location.respond_to?(:line) ? location.line : location&.fetch(:line, nil)
    column = location.respond_to?(:column) ? location.column : location&.fetch(:column, nil)
    {
      "status" => "rejected",
      "message" => e.message,
      "token" => e.token_name,
      "expected" => e.expected_tokens,
      "state" => e.state,
      "line" => line,
      "column" => column,
      "suggestions" => e.suggestions
    }
  end

  def observe_racc(parser_class, input)
    parser_class.new.parse(input)
    { "status" => "accepted" }
  rescue StandardError => e
    return { "status" => "error", "class" => e.class.name, "message" => e.message } unless
      e.respond_to?(:token) && e.respond_to?(:value)

    {
      "status" => "rejected",
      "token" => e.token,
      "value" => e.value,
      "message" => e.message
    }
  end

  def observe_repair(parser_class, input)
    parser = parser_class.new
    parser.repair_policy = Ibex::Runtime::RepairPolicy.new
    plan = nil
    parser.define_singleton_method(:on_repair) { |selected| plan = selected }
    parser.parse(input)
    {
      "status" => plan ? "repaired" : "accepted",
      "plan" => plan&.to_h
    }
  rescue StandardError => e
    {
      "status" => "failed",
      "class" => e.class.name,
      "message" => e.message,
      "plan" => plan&.to_h
    }
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV == ["--write"]
    ErrorUXSnapshot.write
    puts "wrote #{ErrorUXSnapshot::SNAPSHOT}"
  elsif ARGV.empty?
    exit(ErrorUXSnapshot.verify? ? 0 : 1)
  else
    abort "usage: ruby tool/error_ux_snapshot.rb [--write]"
  end
end
