# frozen_string_literal: true

require_relative "test_helper"
require "ibex/verifiable_generation_bundle"
require "tmpdir"

class VerifiableGenerationBundleIdentityTest < Minitest::Test
  SOURCE = "class BundleParser\ntoken ITEM\nrule\nstart: ITEM\nend\n"

  def test_multi_file_bundle_identity_is_checkout_independent_and_content_bound
    Dir.mktmpdir("ibex-verifiable-left") do |left|
      Dir.mktmpdir("ibex-verifiable-right") do |right|
        Dir.mktmpdir("ibex-verifiable-changed") do |changed|
          left_result = checkout_bundle(left, "item: ITEM\n")
          right_result = checkout_bundle(right, "item: ITEM\n")
          changed_result = checkout_bundle(changed, "item: ITEM ITEM\n")

          assert_checkout_independent(left_result, right_result)
          assert_content_bound(left_result, changed_result)
        end
      end
    end
  end

  def test_raw_path_table_cannot_be_paired_with_a_canonical_report
    with_input("grammar.y") do |input|
      automaton = automaton(SOURCE, "grammar.y")
      raw_table = Ibex::TableArtifact.build(automaton)

      error = assert_raises(ArgumentError) do
        Ibex::VerificationReport.render(
          automaton, table: raw_table, source_records: [input], table_path: "parser.tables.ibex.json"
        )
      end
      assert_equal "table artifact does not match the supplied Automaton IR", error.message
      assert_equal automaton.grammar_digest, raw_table.identity.fetch("grammar_digest")
    end
  end

  def test_canonical_identity_rejects_an_unmapped_ir_file
    with_input("other.y") do |input|
      error = assert_raises(ArgumentError) do
        Ibex::VerificationReport.canonical_automaton(automaton(SOURCE, "grammar.y"), source_records: [input])
      end
      assert_includes error.message, "is not present in source_records"
    end
  end

  def test_canonical_identity_rejects_an_ambiguous_relative_basename
    Dir.mktmpdir("ibex-verifiable-ambiguous") do |directory|
      inputs = %w[left right].map do |name|
        child = File.join(directory, name)
        Dir.mkdir(child)
        generation_input(child, "grammar.y", SOURCE)
      end

      error = assert_raises(ArgumentError) do
        Ibex::VerificationReport.canonical_automaton(automaton(SOURCE, "grammar.y"), source_records: inputs)
      end
      assert_includes error.message, "matches multiple source_records"
    end
  end

  def test_canonical_automaton_is_idempotent_and_matches_table_and_report_claims
    with_input("grammar.y") do |input|
      first = Ibex::VerificationReport.canonical_automaton(automaton(SOURCE, "grammar.y"), source_records: [input])
      second = Ibex::VerificationReport.canonical_automaton(first, source_records: [input])
      table = Ibex::TableArtifact.build(second)
      report = JSON.parse(
        Ibex::VerificationReport.render(
          second, table: table, source_records: [input], table_path: "parser.tables.ibex.json"
        )
      )

      assert_equal Ibex::IR::Serialize.dump(first), Ibex::IR::Serialize.dump(second)
      assert_equal "source-logical-v1", report.dig("ir", "identity_scope")
      assert_equal table.identity.fetch("grammar_digest"), report.dig("ir", "grammar", "digest")
      assert_equal table.identity.fetch("automaton_digest"), report.dig("ir", "automaton", "digest")
      assert_equal table.identity.fetch("payload_digest"), report.dig("table", "payload_digest")
    end
  end

  private

  def assert_checkout_independent(left, right)
    refute_equal Ibex::IR::Serialize.dump(left.fetch(:automaton)),
                 Ibex::IR::Serialize.dump(right.fetch(:automaton))
    assert_original_provenance(left)
    assert_original_provenance(right)
    assert_equal artifact_content(left, :parser_table), artifact_content(right, :parser_table)
    assert_equal artifact_content(left, :verification_report), artifact_content(right, :verification_report)
    assert_equal evidence_digest(left), evidence_digest(right)
  end

  def assert_content_bound(original, changed)
    refute_equal artifact_content(original, :parser_table), artifact_content(changed, :parser_table)
    refute_equal artifact_content(original, :verification_report), artifact_content(changed, :verification_report)
    refute_equal evidence_digest(original), evidence_digest(changed)
  end

  def assert_original_provenance(result)
    automaton = result.fetch(:automaton)
    expected = File.realpath(File.join(result.fetch(:directory), "grammar.y"))
    assert_equal expected, automaton.grammar.symbol("ITEM").location.fetch(:file)
  end

  def checkout_bundle(directory, fragment_source)
    root_source = <<~GRAMMAR
      class BundleParser
      token ITEM
      include "rules.y"
      rule
      start: item
      end
    GRAMMAR
    root_path = File.join(directory, "grammar.y")
    File.binwrite(root_path, root_source)
    File.binwrite(File.join(directory, "rules.y"), "fragment\nrule\n#{fragment_source}end\n")
    loader = Ibex::Frontend::SourceLoader.new(record_reads: true)
    resolver = Ibex::Frontend::Resolver.new(root_path, mode: :extended, loader: loader)
    automaton = Ibex::LALR::Builder.new(Ibex::Normalizer.new(resolver.resolve).normalize).build
    bundle = build_bundle(directory, automaton, resolver.source_records)
    { directory: directory, automaton: automaton, artifacts: artifacts_by_kind(bundle.render) }
  end

  def build_bundle(directory, automaton, source_records)
    Ibex::VerifiableGenerationBundle.new(
      automaton,
      wrapper_path: File.join(directory, "parser.rb"),
      wrapper_source: Ibex::Codegen::Ruby.new(automaton).generate,
      table_path: File.join(directory, "parser.tables.ibex.json"),
      report_path: File.join(directory, "parser.verification.ibex.json"),
      manifest_path: File.join(directory, "manifest.ibex.json"),
      source_records: source_records,
      manifest_options: { "table" => "compact" }
    )
  end

  def with_input(basename)
    Dir.mktmpdir("ibex-verifiable-input") do |directory|
      yield generation_input(directory, basename, SOURCE)
    end
  end

  def generation_input(directory, basename, source)
    path = File.join(directory, basename)
    File.binwrite(path, source)
    Ibex::GenerationInput.new(path, source)
  end

  def automaton(source, file)
    ast = Ibex::Frontend::Parser.new(source, file: file).parse
    Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
  end

  def artifacts_by_kind(artifacts)
    artifacts.to_h { |artifact| [artifact.kind, artifact] }
  end

  def artifact_content(result, kind)
    result.dig(:artifacts, kind).content
  end

  def evidence_digest(result)
    JSON.parse(artifact_content(result, :verification_report)).fetch("evidence_digest")
  end
end
