# frozen_string_literal: true

require_relative "test_helper"
require "json_schemer"
require "stringio"
require "tempfile"

class CLIVerifyTest < Minitest::Test
  def test_verify_emits_a_schema_valid_report
    with_automaton do |path|
      output = StringIO.new

      status = Ibex::CLI.start(["verify", "--strict", path], stdout: output, stderr: StringIO.new)
      report = JSON.parse(output.string)
      schema_path = File.expand_path("../schema/verify-v1.schema.json", __dir__)

      assert_equal 0, status
      assert_equal "valid", report.fetch("result")
      assert_empty JSONSchemer.schema(JSON.parse(File.binread(schema_path))).validate(report).to_a
    end
  end

  def test_verify_returns_one_for_a_semantic_violation
    with_automaton do |path|
      document = JSON.parse(File.binread(path))
      document.fetch("states").first.fetch("items").shift
      File.binwrite(path, JSON.pretty_generate(document))
      output = StringIO.new

      status = Ibex::CLI.start(["verify", path], stdout: output, stderr: StringIO.new)

      assert_equal 1, status
      assert_equal "invalid", JSON.parse(output.string).fetch("result")
    end
  end

  def test_verify_returns_two_when_a_reference_budget_is_exhausted
    with_automaton do |path|
      output = StringIO.new

      status = Ibex::CLI.start(["verify", "--max-states=1", path], stdout: output, stderr: StringIO.new)

      assert_equal 2, status
      assert_equal "budget_exhausted", JSON.parse(output.string).fetch("result")
    end
  end

  def test_verify_rejects_grammar_ir_as_the_primary_input
    Tempfile.create(["grammar", ".json"]) do |file|
      file.write(Ibex::IR::Serialize.dump(calculator_automaton.grammar))
      file.flush
      errors = StringIO.new

      status = Ibex::CLI.start(["verify", file.path], stdout: StringIO.new, stderr: errors)

      assert_equal 1, status
      assert_includes errors.string, "verify requires Automaton IR"
    end
  end

  def test_verify_does_not_execute_user_actions
    source = <<~GRAMMAR
      class SafeParser
      rule
      start: TOKEN { raise "must not execute" }
      end
    GRAMMAR
    grammar = normalize(source, "safe.y")
    automaton = Ibex::LALR::Builder.new(grammar).build
    Tempfile.create(["automaton", ".json"]) do |file|
      file.write(Ibex::IR::Serialize.dump(automaton))
      file.flush

      assert_equal 0, Ibex::CLI.start(["verify", file.path], stdout: StringIO.new, stderr: StringIO.new)
    end
  end

  private

  def with_automaton
    Tempfile.create(["automaton", ".json"]) do |file|
      file.write(Ibex::IR::Serialize.dump(calculator_automaton))
      file.flush
      yield file.path
    end
  end

  def calculator_automaton
    path = File.expand_path("../gallery/calc/grammar.y", __dir__)
    Ibex::LALR::Builder.new(normalize(File.binread(path), path)).build
  end

  def normalize(source, file)
    ast = Ibex::Frontend::Parser.new(source, file: file, mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended).normalize
  end
end
