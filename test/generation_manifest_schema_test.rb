# frozen_string_literal: true

require_relative "test_helper"
require "json_schemer"

class GenerationManifestSchemaTest < Minitest::Test
  def test_v1_options_accept_additive_effective_configuration_evidence
    contract = JSON.parse(File.read(File.expand_path("../schema/generation-manifest-v1.schema.json", __dir__)))
    options = contract.dig("properties", "options")
    document = {
      "ibex_manifest" => "generation",
      "schema_version" => 1,
      "input" => {
        "root" => "/grammar.y",
        "sha256" => "0" * 64,
        "files" => [{ "path" => "/grammar.y", "sha256" => "1" * 64, "bytesize" => 1 }]
      },
      "options" => { "cst_trivia" => "leading" },
      "artifacts" => [{ "kind" => "parser", "path" => "/parser.rb", "sha256" => "2" * 64,
                        "bytesize" => 1 }]
    }

    assert_equal 1, contract.dig("properties", "schema_version", "const")
    refute options.key?("additionalProperties")
    assert_empty JSONSchemer.schema(contract).validate(document).to_a
  end
end
