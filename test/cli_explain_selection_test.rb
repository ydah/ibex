# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLIExplainSelectionTest < Minitest::Test
  def test_selector_searches_only_matching_conflicts
    source = <<~GRAMMAR
      class P
      token NUM
      expect 4
      rule
      expr: expr '+' expr
          | expr '*' expr
          | NUM
      end
    GRAMMAR
    automaton = build_automaton(source)
    state = automaton.states.find { |candidate| candidate.conflicts.length > 1 }
    token = state.conflicts.first.fetch(:symbol)
    calls = []
    search = Object.new
    search.define_singleton_method(:call) { nil }
    factory = lambda do |_automaton, selected_state, conflict, **_options|
      calls << [selected_state.id, conflict.fetch(:symbol)]
      search
    end

    with_grammar(source) do |path|
      Ibex::LALR::ConflictSearch.stub(:new, factory) do
        result = invoke(["explain", "--format=json", "--state=#{state.id}", "--token=#{token}", path])
        document = JSON.parse(result.fetch(:stdout))
        assert_equal document.dig("summary", "matched_conflicts"), calls.length
        assert(calls.all? { |state_id, symbol| state_id == state.id && symbol == token })
      end
    end
  end

  private

  def build_automaton(source)
    ast = Ibex::Frontend::Parser.new(source, file: "explain-selection.y").parse
    Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
  end

  def invoke(arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
    { status: status, stdout: stdout.string, stderr: stderr.string }
  end

  def with_grammar(source)
    Dir.mktmpdir("ibex-explain-selection") do |directory|
      path = File.join(directory, "grammar.y")
      File.write(path, source)
      yield path
    end
  end
end
