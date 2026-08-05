# frozen_string_literal: true

require_relative "test_helper"

class ConfigurationExplanationTest < Minitest::Test
  def test_report_is_deterministic_across_input_hash_order
    key = Ibex::Configuration::Registry.fetch("parser.algorithm")
    location = Ibex::Location.new(file: "contract.y", line: 3, column: 4)
    evidence = Ibex::Configuration::Evidence.new(
      key, source: :grammar, value: :ielr, status: :accepted, location: location, reason: "contract"
    )
    recording = Ibex::Configuration::Recording.new(:recorded, "recorded contract")
    first = input(
      grammar_values: { "parser.algorithm" => :ielr, "grammar.mode" => :extended },
      grammar_locations: { "parser.algorithm" => location, "grammar.mode" => location },
      evidence: { "parser.algorithm" => [evidence] }, recordings: { "parser.algorithm" => recording }
    )
    second = input(
      grammar_values: { "grammar.mode" => :extended, "parser.algorithm" => :ielr },
      grammar_locations: { "grammar.mode" => location, "parser.algorithm" => location },
      recordings: { "parser.algorithm" => recording }, evidence: { "parser.algorithm" => [evidence] }
    )

    assert_equal Ibex::Configuration::Report.new(first).dump, Ibex::Configuration::Report.new(second).dump
  end

  def test_conflict_remains_a_typed_deterministic_report
    key = Ibex::Configuration::Registry.fetch("parser.algorithm")
    location = Ibex::Location.new(file: "contract.y", line: 7, column: 2)
    grammar = input(
      grammar_values: { key.name => :ielr }, grammar_locations: { key.name => location },
      evidence: {
        key.name => [Ibex::Configuration::Evidence.new(
          key, source: :grammar, value: :ielr, status: :accepted, location: location, reason: "contract"
        )]
      }
    )

    report = Ibex::Configuration::Report.new(grammar, cli: { key.name => :lalr })
    explanation = report.explanations.find { |entry| entry.value.key.equal?(key) }
    conflict = report.conflicts.fetch(0)

    refute report.success?
    assert_equal :ielr, conflict.declared.value
    assert_equal location, conflict.declared.origin.location
    assert_equal :lalr, conflict.requested.value
    assert_equal %i[accepted conflicting], explanation.evidence.map(&:status)
    assert_equal "conflict", JSON.parse(report.dump).fetch("status")
  end

  def test_input_is_immutable_and_rejects_invalid_external_shape
    path = +"grammar.y"
    files = [path]
    report_input = input(path: path, files: files)
    path << ".changed"
    files << "other.y"

    assert_equal "grammar.y", report_input.path
    assert_equal ["grammar.y"], report_input.files
    assert report_input.frozen?
    assert report_input.files.frozen?
    assert_raises(ArgumentError) { input(path: "grammar.y", files: ["other.y"]) }
    assert_raises(ArgumentError) { input(path: "grammar.y", files: ["grammar.y", "grammar.y"]) }
    assert_raises(ArgumentError) do
      Ibex::Configuration::Input.new(kind: :grammar_ir, path: "grammar.json", schema_version: nil)
    end
    assert_raises(ArgumentError) { input(grammar_values: { "unknown.key" => true }) }
  end

  def test_ignored_and_duplicate_evidence_are_preserved_without_inventing_selection
    key = Ibex::Configuration::Registry.fetch("parser.algorithm")
    ignored = Ibex::Configuration::Evidence.new(
      key, source: :grammar, value: :slr, status: :ignored, reason: "unavailable historical source"
    )
    duplicate = Ibex::Configuration::Evidence.new(
      key, source: :grammar, value: :lalr, status: :duplicate, reason: "same declaration repeated"
    )
    report = Ibex::Configuration::Report.new(input(evidence: { key.name => [ignored, duplicate] }))
    explanation = report.explanations.find { |entry| entry.value.key.equal?(key) }

    assert_equal :lalr, explanation.value.value
    assert_equal :builtin, explanation.value.origin.kind
    assert_equal %i[ignored duplicate], explanation.evidence.map(&:status)
  end

  private

  def input(path: "grammar.y", files: [path], grammar_values: {}, grammar_locations: {}, evidence: {}, recordings: {})
    Ibex::Configuration::Input.new(
      kind: :grammar_source, path: path, files: files, grammar_values: grammar_values,
      grammar_locations: grammar_locations, evidence: evidence, recordings: recordings
    )
  end
end
