# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"

class ImpactCLIAdversarialTest < Minitest::Test
  def test_unreachable_comparison_uses_state_content_not_numeric_ids
    grammar = normalize_grammar("class P\ntoken TOKEN\nrule\nstart: TOKEN\nend\n")
    base = Ibex::LALR::Builder.new(grammar).build
    before = automaton_with_unreachable(base, [base.states.fetch(0)])
    after = automaton_with_unreachable(base, [base.states.fetch(1), base.states.fetch(0)])
    cli = Ibex::CLI.new(stdout: StringIO.new, stderr: StringIO.new)
    cli.extend(Ibex::CLIImpact)

    assert_equal [base.states.length], cli.send(:newly_unreachable_state_ids, before, after)
  end

  private

  def normalize_grammar(source)
    ast = Ibex::Frontend::Parser.new(source, file: "impact-cli.y").parse
    Ibex::Normalizer.new(ast).normalize
  end

  def automaton_with_unreachable(base, source_states)
    extras = source_states.each_with_index.map do |state, index|
      Ibex::IR::AutomatonState.new(
        id: base.states.length + index, items: state.items, transitions: {}, actions: {}, gotos: {},
        default_action: nil, conflicts: []
      )
    end
    Ibex::IR::Automaton.new(
      grammar: base.grammar, states: base.states + extras, conflict_summary: base.conflict_summary,
      algorithm: base.algorithm, grammar_digest: base.grammar_digest, entry_states: base.entry_states,
      entry_construction: base.entry_construction
    )
  end
end
