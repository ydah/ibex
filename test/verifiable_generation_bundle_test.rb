# frozen_string_literal: true

require_relative "test_helper"
require "ibex/verifiable_generation_bundle"
require "tmpdir"

class VerifiableGenerationBundleTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class BundleParser
    token ITEM
    rule
    start: ITEM
    end
  GRAMMAR

  OTHER_SOURCE = <<~GRAMMAR
    class OtherBundleParser
    token VALUE
    rule
    start: VALUE VALUE
    end
  GRAMMAR

  def test_render_orders_manifest_last_and_binds_every_artifact
    Dir.mktmpdir("ibex-verifiable-bundle") do |directory|
      artifacts = bundle(directory, SOURCE).render
      kinds = artifacts.map(&:kind)
      manifest = JSON.parse(artifacts.to_a.last.content)

      assert_equal %i[parser_table parser verification_report manifest], kinds
      assert_equal(%w[parser_table parser verification_report],
                   manifest.fetch("artifacts").map { |entry| entry.fetch("kind") })
      assert_equal "verification_report", manifest.dig("artifacts", 2, "kind")
      assert_match(/\A[0-9a-f]{64}\z/, manifest.dig("artifacts", 2, "sha256"))
      refute_includes artifacts.to_a.fetch(2).content, File.join(directory, "manifest.ibex.json")
    end
  end

  def test_publish_uses_transaction_and_validates_the_complete_bundle
    Dir.mktmpdir("ibex-verifiable-bundle") do |directory|
      value = bundle(directory, SOURCE)
      artifacts = value.publish
      manifest_path = artifacts.find { |artifact| artifact.kind == :manifest }.path
      report = Ibex::VerifiableGenerationBundle.validate_file(manifest_path)

      assert_equal "pass", report.dig("outcome", "status")
      artifacts.each { |artifact| assert_equal artifact.content, File.binread(artifact.path) }
    end
  end

  def test_stale_report_is_rejected_even_when_its_internal_digest_is_resigned
    Dir.mktmpdir("ibex-verifiable-bundle") do |directory|
      sources = artifact_sources(bundle(directory, SOURCE).render)
      document = JSON.parse(sources.fetch(:verification_report))
      document.fetch("checker")["version"] = "9.9.9"
      resign_report!(document)

      error = assert_raises(Ibex::VerificationReport::ValidationError) do
        Ibex::VerificationReport.validate_bundle(
          manifest_source: sources.fetch(:manifest),
          report_source: Ibex::TableArtifact::Serializer.dump(document),
          table_source: sources.fetch(:parser_table)
        )
      end
      assert_includes error.message, "verification report manifest digest mismatch"
    end
  end

  def test_report_from_another_table_is_rejected_after_manifest_is_rebound
    Dir.mktmpdir("ibex-verifiable-a") do |left|
      Dir.mktmpdir("ibex-verifiable-b") do |right|
        left_bundle = bundle(left, SOURCE).render
        right_bundle = bundle(right, OTHER_SOURCE).render
        left_sources = artifacts_by_kind(left_bundle)
        right_sources = artifacts_by_kind(right_bundle)
        mixed = Ibex::ArtifactSet.new
        mixed.add(kind: :parser_table, path: left_sources.fetch(:parser_table).path,
                  content: left_sources.fetch(:parser_table).content)
        mixed.add(kind: :parser, path: left_sources.fetch(:parser).path, content: left_sources.fetch(:parser).content)
        mixed.add(kind: :verification_report, path: left_sources.fetch(:verification_report).path,
                  content: right_sources.fetch(:verification_report).content)
        manifest = Ibex::GenerationManifest.render(
          mixed, source_records: source_records(right, OTHER_SOURCE), options: {}
        )

        error = assert_raises(Ibex::VerificationReport::ValidationError) do
          Ibex::VerificationReport.validate_bundle(
            manifest_source: manifest,
            report_source: right_sources.fetch(:verification_report).content,
            table_source: left_sources.fetch(:parser_table).content
          )
        end
        assert_includes error.message, "table.artifact_digest mismatch"
      end
    end
  end

  def test_resigned_logical_input_name_must_match_manifest_input_role
    Dir.mktmpdir("ibex-verifiable-bundle") do |directory|
      rendered = bundle(directory, SOURCE).render
      by_kind = artifacts_by_kind(rendered)
      document = JSON.parse(by_kind.fetch(:verification_report).content)
      document.dig("input", "files", 0)["logical_path"] = "input/0000/other.y"
      document.fetch("input")["digest"] = Ibex::TableArtifact::Serializer.digest(document.dig("input", "files"))
      resign_report!(document)
      report_source = Ibex::TableArtifact::Serializer.dump(document)
      rebound = Ibex::ArtifactSet.new
      %i[parser_table parser].each do |kind|
        artifact = by_kind.fetch(kind)
        rebound.add(kind: kind, path: artifact.path, content: artifact.content)
      end
      report_artifact = by_kind.fetch(:verification_report)
      rebound.add(kind: :verification_report, path: report_artifact.path, content: report_source)
      manifest = Ibex::GenerationManifest.render(
        rebound, source_records: source_records(directory, SOURCE), options: {}
      )

      error = assert_raises(Ibex::VerificationReport::ValidationError) do
        Ibex::VerificationReport.validate_bundle(
          manifest_source: manifest, report_source: report_source,
          table_source: by_kind.fetch(:parser_table).content
        )
      end
      assert_includes error.message, "report input identity does not match manifest input"
    end
  end

  def test_manifest_from_another_input_is_rejected
    Dir.mktmpdir("ibex-verifiable-a") do |left|
      Dir.mktmpdir("ibex-verifiable-b") do |right|
        artifacts = bundle(left, SOURCE).render
        by_kind = artifacts_by_kind(artifacts)
        without_manifest = Ibex::ArtifactSet.new
        %i[parser_table parser verification_report].each do |kind|
          artifact = by_kind.fetch(kind)
          without_manifest.add(kind: kind, path: artifact.path, content: artifact.content, mode: artifact.mode)
        end
        mismatched_manifest = Ibex::GenerationManifest.render(
          without_manifest, source_records: source_records(right, OTHER_SOURCE), options: {}
        )

        error = assert_raises(Ibex::VerificationReport::ValidationError) do
          Ibex::VerificationReport.validate_bundle(
            manifest_source: mismatched_manifest,
            report_source: by_kind.fetch(:verification_report).content,
            table_source: by_kind.fetch(:parser_table).content
          )
        end
        assert_includes error.message, "report input identity does not match manifest input"
      end
    end
  end

  def test_manifest_without_report_is_rejected
    Dir.mktmpdir("ibex-verifiable-bundle") do |directory|
      rendered = bundle(directory, SOURCE).render
      by_kind = artifacts_by_kind(rendered)
      incomplete = Ibex::ArtifactSet.new
      %i[parser_table parser].each do |kind|
        artifact = by_kind.fetch(kind)
        incomplete.add(kind: kind, path: artifact.path, content: artifact.content)
      end
      manifest = Ibex::GenerationManifest.render(
        incomplete, source_records: source_records(directory, SOURCE), options: {}
      )

      error = assert_raises(Ibex::VerificationReport::ValidationError) do
        Ibex::VerificationReport.validate_bundle(
          manifest_source: manifest,
          report_source: by_kind.fetch(:verification_report).content,
          table_source: by_kind.fetch(:parser_table).content
        )
      end
      assert_includes error.message, "exactly one verification_report"
    end
  end

  private

  def bundle(directory, source)
    value = automaton(source)
    Ibex::VerifiableGenerationBundle.new(
      value,
      wrapper_path: File.join(directory, "parser.rb"),
      wrapper_source: Ibex::Codegen::Ruby.new(value).generate,
      table_path: File.join(directory, "parser.tables.ibex.json"),
      report_path: File.join(directory, "parser.verification.ibex.json"),
      manifest_path: File.join(directory, "manifest.ibex.json"),
      source_records: source_records(directory, source),
      manifest_options: { "table" => "compact" }
    )
  end

  def source_records(directory, source)
    path = File.join(directory, "grammar.y")
    File.binwrite(path, source)
    [Ibex::GenerationInput.new(path, source)]
  end

  def automaton(source)
    ast = Ibex::Frontend::Parser.new(source, file: "grammar.y").parse
    Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
  end

  def artifact_sources(artifacts)
    artifacts.to_h { |artifact| [artifact.kind, artifact.content] }
  end

  def artifacts_by_kind(artifacts)
    artifacts.to_h { |artifact| [artifact.kind, artifact] }
  end

  def resign_report!(document)
    document.delete("evidence_digest")
    document["evidence_digest"] = Ibex::TableArtifact::Serializer.digest(document)
  end
end
