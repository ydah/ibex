# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/docs_coverage"
require "fileutils"
require "tmpdir"

class DocsCoverageTest < Minitest::Test
  def test_accepts_the_reviewed_contract_revision
    with_contract_documents do |root|
      Ibex::Quality::DocsCoverage.new(root: root).verify!
    end
  end

  def test_rejects_a_one_sided_contract_revision_update
    with_contract_documents(en_revision: 2) do |root|
      error = assert_raises(RuntimeError) do
        Ibex::Quality::DocsCoverage.new(root: root).verify!
      end

      assert_includes error.message, "only"
      assert_includes error.message, "stable:example:v1"
    end
  end

  def test_rejects_a_nonpositive_contract_revision
    with_contract_documents(contract_revision: 0, en_revision: 0) do |root|
      error = assert_raises(RuntimeError) do
        Ibex::Quality::DocsCoverage.new(root: root).verify!
      end

      assert_includes error.message, "contract_revision must be a positive integer"
    end
  end

  private

  # rubocop:disable Metrics/BlockLength -- the fixture mirrors the complete gate input.
  def with_contract_documents(contract_revision: 1, en_revision: contract_revision)
    Dir.mktmpdir("ibex-docs-coverage") do |root|
      FileUtils.mkdir_p(File.join(root, "docs/decisions"))
      FileUtils.mkdir_p(File.join(root, "docs/registry"))
      File.binwrite(File.join(root, "README.md"), Ibex::Quality::DocsCoverage::REQUIRED_CLI_TERMS.join("\n"))
      File.binwrite(File.join(root, "docs/grammar-reference.md"), <<~MARKDOWN)
        ---
        title: Grammar reference
        description: Example
        ---
        <!-- stable:example:v#{en_revision} -->
      MARKDOWN
      File.binwrite(File.join(root, "docs/README.md"), "# Documentation\n")
      File.binwrite(File.join(root, "docs/decisions/README.md"), "# Decisions\n")
      File.binwrite(File.join(root, "docs/index.yml"), <<~YAML)
        version: 1
        documents:
          - slug: grammar-reference
            path: grammar-reference.md
        assets: []
      YAML
      File.binwrite(File.join(root, "docs/registry/stable-features.yml"), <<~YAML)
        version: 3
        features:
          example:
            contract_revision: #{contract_revision}
            en: docs/grammar-reference.md
      YAML
      yield root
    end
  end
  # rubocop:enable Metrics/BlockLength
end
