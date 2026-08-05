# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/verifier_fault_corpus"

class VerifyVerifierTest < Minitest::Test
  include Ibex::TestSupport::VerifierFaultCorpus

  GALLERY_ALGORITHMS = %i[slr lalr ielr lr1].freeze
  FAULTS = Ibex::TestSupport::VerifierFaultCorpus::FAULTS

  def test_all_gallery_automata_pass_default_and_strict_verification
    Dir.glob(File.expand_path("../../gallery/*/grammar.y", __dir__)).each do |path|
      grammar = normalize(File.binread(path), file: path)
      GALLERY_ALGORITHMS.each do |algorithm|
        automaton = Ibex::LALR::Builder.new(grammar, algorithm: algorithm).build

        [false, true].each do |strict|
          result = Ibex::Verify::Verifier.new(automaton, strict: strict).verify
          assert result.valid?,
                 "#{path} #{algorithm} strict=#{strict}: #{result.violations.map(&:to_h).inspect}"
        end
      end
    end
  end

  def test_twenty_structurally_valid_fault_types_are_all_detected
    assert_equal 20, FAULTS.length

    FAULTS.each do |fault|
      document = fault == :epsilon_cycle ? epsilon_document : calculator_document
      inject_fault(document, fault)
      automaton = Ibex::IR::Validator.validate(JSON.generate(document))
      assert_instance_of Ibex::IR::Automaton, automaton, fault

      result = Ibex::Verify::Verifier.new(automaton, strict: true).verify
      refute result.valid?, "#{fault} escaped verification"
    end
  end

  def test_epsilon_cycle_is_reported_as_a_termination_violation
    document = epsilon_document
    inject_fault(document, :epsilon_cycle)
    automaton = Ibex::IR::Validator.validate(JSON.generate(document))

    result = Ibex::Verify::Verifier.new(automaton).verify

    assert_includes result.violations.map(&:id), "V7"
  end

  def test_unreachable_state_is_reported
    document = calculator_document
    inject_fault(document, :add_unreachable_state)
    automaton = Ibex::IR::Validator.validate(JSON.generate(document))

    result = Ibex::Verify::Verifier.new(automaton).verify

    assert_includes result.violations.map(&:id), "V6"
  end

  def test_reference_implementation_does_not_reference_the_builder
    root = File.expand_path("../../lib/ibex/verify", __dir__)
    source = Dir.glob("#{root}/**/*.rb").map { |path| File.binread(path) }.join

    refute_includes source, "LALR::Builder"
    refute_includes source, "lalr/builder"
  end

  def test_multiple_entries_and_isolated_entries_preserve_augmented_item_identity
    grammar = normalize(<<~GRAMMAR, file: "entries.y")
      class EntriesParser
      pragma extended
      start program expression
      rule
      program: A B
      expression: A
      end
    GRAMMAR

    GALLERY_ALGORITHMS.product([false, true]).each do |algorithm, entry_isolation|
      automaton = Ibex::LALR::Builder.new(
        grammar, algorithm: algorithm, entry_isolation: entry_isolation
      ).build
      result = Ibex::Verify::Verifier.new(automaton, strict: true).verify

      assert result.valid?,
             "#{algorithm} entry_isolation=#{entry_isolation}: #{result.violations.map(&:to_h).inspect}"
    end
  end

  def test_reference_collection_has_explicit_state_and_item_budgets
    automaton = build_calculator

    assert_raises(Ibex::Verify::BudgetExceeded) do
      Ibex::Verify::Verifier.new(automaton, max_states: 1).verify
    end
    assert_raises(Ibex::Verify::BudgetExceeded) do
      Ibex::Verify::Verifier.new(automaton, max_items: 1).verify
    end
  end
end
