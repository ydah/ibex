# frozen_string_literal: true

require_relative "test_helper"
require "ibex/verifiable_generation_bundle"
require "ibex/ir/validator"
require "tmpdir"

class VerificationReportTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class VerificationReportParser
    token ITEM
    rule
    start: items
    items: items ITEM |
    end
  GRAMMAR

  OTHER_SOURCE = <<~GRAMMAR
    class OtherVerificationReportParser
    token VALUE
    rule
    start: VALUE
    end
  GRAMMAR

  def test_report_records_scoped_default_verification_and_excluded_trust
    Dir.mktmpdir("ibex-verification-report") do |directory|
      report = render_report(automaton, input_for(directory, SOURCE))
      document = Ibex::VerificationReport.validate(report)

      assert_equal "scoped_verification", document.fetch("ibex_report")
      assert_equal "source-logical-v1", document.dig("ir", "identity_scope")
      assert_equal "default", document.fetch("profile")
      assert_equal "pass", document.dig("outcome", "status")
      assert_equal Ibex::Verify::Verifier::DEFAULT_CHECKS, document.dig("outcome", "executed_checks")
      assert_equal Ibex::VerificationReport::EXCLUDED_TRUST, document.fetch("excluded_trust")
      assert_includes document.fetch("excluded_trust"), "table_semantic_derivation"
      assert_equal false, report.include?(File.expand_path(directory))
      refute_includes report, "manifest_digest"
      refute_includes report, "semantic action must be verified"
    end
  end

  def test_strict_and_exhausted_outcomes_distinguish_executed_checks
    Dir.mktmpdir("ibex-verification-report") do |directory|
      input = input_for(directory, SOURCE)
      strict = JSON.parse(render_report(automaton, input, strict: true))
      exhausted = JSON.parse(render_report(automaton, input, max_states: 1))

      assert_equal "strict", strict.fetch("profile")
      assert_equal Ibex::Verify::Verifier::DEFAULT_CHECKS + Ibex::Verify::Verifier::STRICT_CHECKS,
                   strict.dig("outcome", "executed_checks")
      assert_equal "exhausted", exhausted.dig("outcome", "status")
      assert_empty exhausted.dig("outcome", "executed_checks")
      assert_equal "reference_collection_budget", exhausted.dig("outcome", "exhaustion", "kind")
      assert Ibex::VerificationReport.validate(Ibex::TableArtifact::Serializer.dump(exhausted))
    end
  end

  def test_semantic_violation_is_distinct_from_exhaustion
    Dir.mktmpdir("ibex-verification-report") do |directory|
      document = JSON.parse(Ibex::IR::Serialize.dump(automaton))
      state = document.fetch("states").find { |entry| entry.fetch("items").length > 1 }
      state.fetch("items").shift
      faulty = Ibex::IR::Validator.validate(JSON.generate(document))
      input = input_for(directory, SOURCE)
      canonical = Ibex::VerificationReport.canonical_automaton(faulty, source_records: [input])
      table = Ibex::TableArtifact.build(canonical)
      report = Ibex::VerificationReport.render(
        canonical, table: table, source_records: [input], table_path: "parser.tables.ibex.json", strict: true
      )
      outcome = Ibex::VerificationReport.validate(report).fetch("outcome")

      assert_equal "violations", outcome.fetch("status")
      refute_empty outcome.fetch("violations")
      assert_nil outcome.fetch("exhaustion")
    end
  end

  def test_report_identity_does_not_depend_on_absolute_checkout_path
    Dir.mktmpdir("ibex-verification-left") do |left|
      Dir.mktmpdir("ibex-verification-right") do |right|
        left_report = render_report(automaton, input_for(left, SOURCE))
        right_report = render_report(automaton, input_for(right, SOURCE))

        assert_equal left_report, right_report
      end
    end
  end

  def test_report_rejects_resigned_scope_expansion
    Dir.mktmpdir("ibex-verification-report") do |directory|
      document = JSON.parse(render_report(automaton, input_for(directory, SOURCE)))
      document.fetch("excluded_trust").delete("semantic_actions")
      resign_report!(document)

      error = assert_raises(Ibex::VerificationReport::ValidationError) do
        Ibex::VerificationReport.validate(JSON.generate(document))
      end
      assert_includes error.message, "excluded_trust"
    end
  end

  def test_report_rejects_a_different_ir_identity_scope
    Dir.mktmpdir("ibex-verification-report") do |directory|
      document = JSON.parse(render_report(automaton, input_for(directory, SOURCE)))
      document.fetch("ir")["identity_scope"] = "raw-source-path-v1"
      resign_report!(document)

      error = assert_raises(Ibex::VerificationReport::ValidationError) do
        Ibex::VerificationReport.validate(JSON.generate(document))
      end
      assert_includes error.message, "ir.identity_scope mismatch"
    end
  end

  def test_builder_rejects_paths_without_a_canonical_logical_basename_and_excess_inputs
    Dir.mktmpdir("ibex-verification-report") do |directory|
      input = input_for(directory, SOURCE)
      table = Ibex::TableArtifact.build(automaton)

      path_error = assert_raises(ArgumentError) do
        Ibex::VerificationReport.render(
          automaton, table: table, source_records: [input], table_path: "/"
        )
      end
      assert_includes path_error.message, "logical basename"

      count_error = assert_raises(ArgumentError) do
        Ibex::VerificationReport.render(
          automaton, table: table,
                     source_records: Array.new(Ibex::VerificationReport::LogicalPath::MAX_INPUT_FILES + 1, input),
                     table_path: "parser.tables.ibex.json"
        )
      end
      assert_includes count_error.message, "at most 10000 input files"
    end
  end

  def test_validator_rejects_noncanonical_and_control_character_logical_paths
    Dir.mktmpdir("ibex-verification-report") do |directory|
      original = JSON.parse(render_report(automaton, input_for(directory, SOURCE)))

      invalid_logical_paths.each do |kind, paths|
        paths.each do |path|
          document = Marshal.load(Marshal.dump(original))
          set_logical_path(document, kind, path)
          document.fetch("input")["digest"] =
            Ibex::TableArtifact::Serializer.digest(document.dig("input", "files"))
          resign_report!(document)
          error = assert_raises(Ibex::VerificationReport::ValidationError, "#{kind}: #{path.inspect}") do
            Ibex::VerificationReport.validate(JSON.generate(document))
          end
          assert_includes error.message, "logical_path", "#{kind}: #{path.inspect}"
        end
      end
    end
  end

  def test_validator_accepts_unicode_logical_basenames
    Dir.mktmpdir("ibex-verification-report") do |directory|
      input = input_for(directory, SOURCE,
                        basename: "文法.y".b.force_encoding(Encoding::ASCII_8BIT))
      value = build_automaton(SOURCE, input.path)
      document = Ibex::VerificationReport.validate(
        render_report(value, input, table_path: "表.ibex.json")
      )

      assert_equal "input/0000/文法.y", document.dig("input", "files", 0, "logical_path")
      assert_equal "table/表.ibex.json", document.dig("table", "logical_path")
    end
  end

  private

  def render_report(value, input, strict: false, max_states: 100_000, table_path: "parser.tables.ibex.json")
    canonical = Ibex::VerificationReport.canonical_automaton(value, source_records: [input])
    table = Ibex::TableArtifact.build(canonical)
    Ibex::VerificationReport.render(
      canonical, table: table, source_records: [input], table_path: table_path,
                 strict: strict, max_states: max_states
    )
  end

  def invalid_logical_paths
    {
      input: ["input/0000/subdir/x", "input/0000/", "input/0000/x\n", "input/0000/x\r", "input/0000/x\u0001"],
      table: ["table/subdir/x", "table/", "table/x\n", "table/x\r", "table/x\u0001"]
    }
  end

  def set_logical_path(document, kind, path)
    if kind == :input
      document.dig("input", "files", 0)["logical_path"] = path
    else
      document.fetch("table")["logical_path"] = path
    end
  end

  def input_for(directory, source, basename: "grammar.y")
    path = File.join(directory, basename)
    File.binwrite(path, source)
    Ibex::GenerationInput.new(path, source)
  end

  def automaton
    @automaton ||= build_automaton(SOURCE, "grammar.y")
  end

  def build_automaton(source, file)
    ast = Ibex::Frontend::Parser.new(source, file: file).parse
    Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
  end

  def resign_report!(document)
    document.delete("evidence_digest")
    document["evidence_digest"] = Ibex::TableArtifact::Serializer.digest(document)
  end
end
