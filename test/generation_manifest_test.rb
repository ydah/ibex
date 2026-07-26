# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "tmpdir"

class GenerationManifestTest < Minitest::Test
  def test_render_is_deterministic_and_validator_checks_published_artifacts
    Dir.mktmpdir("ibex-manifest") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      File.binwrite(grammar, "class P\n")
      File.binwrite(parser, "# generated\n")
      artifacts = Ibex::ArtifactSet.new
      artifacts.add(kind: :parser, path: parser, content: "# generated\n")
      inputs = [Ibex::GenerationInput.new(grammar, File.binread(grammar))]

      first = Ibex::GenerationManifest.render(
        artifacts, source_records: inputs, options: { "table" => "compact", "algorithm" => "lalr" }
      )
      second = Ibex::GenerationManifest.render(
        artifacts, source_records: inputs, options: { "algorithm" => "lalr", "table" => "compact" }
      )

      assert_equal first, second
      document = Ibex::GenerationManifest.validate(first)
      assert_equal 1, document.fetch("schema_version")
      assert_equal %w[algorithm table], document.fetch("options").keys
      assert_equal File.realpath(grammar), document.dig("input", "root")
    end
  end

  def test_validator_rejects_a_stale_artifact
    Dir.mktmpdir("ibex-manifest") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      File.binwrite(grammar, "class P\n")
      File.binwrite(parser, "# generated\n")
      artifacts = Ibex::ArtifactSet.new
      artifacts.add(kind: :parser, path: parser, content: "# generated\n")
      inputs = [Ibex::GenerationInput.new(grammar, File.binread(grammar))]
      source = Ibex::GenerationManifest.render(artifacts, source_records: inputs, options: {})
      File.binwrite(parser, "# stale\n")

      error = assert_raises(Ibex::Error) { Ibex::GenerationManifest.validate(source) }
      assert_match(/artifact (?:bytesize|digest) mismatch/, error.message)
    end
  end

  def test_render_uses_recorded_bytes_instead_of_rereading_changed_input
    Dir.mktmpdir("ibex-manifest") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      File.binwrite(grammar, "AAAA")
      input = Ibex::GenerationInput.new(grammar, "AAAA")
      File.binwrite(grammar, "BBBB")
      artifacts = Ibex::ArtifactSet.new
      artifacts.add(kind: :parser, path: parser, content: "parser")

      source = Ibex::GenerationManifest.render(artifacts, source_records: [input], options: {})
      document = Ibex::GenerationManifest.validate(source, verify_artifacts: false)

      assert_equal Digest::SHA256.hexdigest("AAAA"), document.dig("input", "files", 0, "sha256")
      refute input.current?
    end
  end

  # Schema validation deliberately exercises several independent invalid shapes.
  # rubocop:disable Metrics/AbcSize
  def test_validator_normalizes_schema_shape_and_type_errors
    Dir.mktmpdir("ibex-manifest") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      File.binwrite(grammar, "grammar")
      artifacts = Ibex::ArtifactSet.new
      artifacts.add(kind: :parser, path: parser, content: "parser")
      input = Ibex::GenerationInput.new(grammar, "grammar")
      valid = JSON.parse(Ibex::GenerationManifest.render(artifacts, source_records: [input], options: {}))
      mutations = [
        ->(document) { document["artifacts"] = [] },
        ->(document) { document["artifacts"][0]["path"] = "" },
        ->(document) { document["artifacts"][0]["kind"] = "" },
        ->(document) { document["artifacts"][0]["kind"] = 1 },
        ->(document) { document["artifacts"][0]["sha256"] = 1 },
        ->(document) { document["artifacts"][0]["path"] = "\0" },
        ->(document) { document["artifacts"][0]["extra"] = true },
        ->(document) { document["extra"] = true }
      ]

      mutations.each do |mutate|
        document = Marshal.load(Marshal.dump(valid))
        mutate.call(document)
        assert_raises(Ibex::Error) do
          Ibex::GenerationManifest.validate(JSON.generate(document), verify_artifacts: false)
        end
      end
    end
  end
  # rubocop:enable Metrics/AbcSize

  def test_validate_file_normalizes_invalid_path_arguments
    error = assert_raises(Ibex::Error) { Ibex::GenerationManifest.validate_file("\0") }
    assert_match(/cannot read generation manifest/, error.message)
  end
end
