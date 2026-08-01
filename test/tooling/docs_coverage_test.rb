# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/docs_coverage"
require "fileutils"
require "tmpdir"

class DocsCoverageTest < Minitest::Test
  def test_accepts_the_same_reviewed_contract_revision_in_both_languages
    with_contract_documents do |root|
      Ibex::Quality::DocsCoverage.new(root: root).verify!
    end
  end

  def test_rejects_a_one_sided_contract_revision_update
    with_contract_documents(ja_revision: 2) do |root|
      error = assert_raises(RuntimeError) do
        Ibex::Quality::DocsCoverage.new(root: root).verify!
      end

      assert_includes error.message, "stable:example:v1"
      assert_includes error.message, "only"
    end
  end

  def test_rejects_a_nonpositive_contract_revision
    with_contract_documents(contract_revision: 0, en_revision: 0, ja_revision: 0) do |root|
      error = assert_raises(RuntimeError) do
        Ibex::Quality::DocsCoverage.new(root: root).verify!
      end

      assert_includes error.message, "contract_revision must be a positive integer"
    end
  end

  private

  def with_contract_documents(contract_revision: 1, en_revision: contract_revision, ja_revision: contract_revision)
    Dir.mktmpdir("ibex-docs-coverage") do |root|
      FileUtils.mkdir_p(File.join(root, "docs/ja"))
      File.binwrite(File.join(root, "README.md"), Ibex::Quality::DocsCoverage::REQUIRED_CLI_TERMS.join("\n"))
      File.binwrite(File.join(root, "docs/grammar-reference.md"), "<!-- stable:example:v#{en_revision} -->\n")
      File.binwrite(File.join(root, "docs/ja/stable-api.md"), "<!-- stable:example:v#{ja_revision} -->\n")
      File.binwrite(File.join(root, "docs/stable-features.yml"), <<~YAML)
        version: 2
        features:
          example:
            contract_revision: #{contract_revision}
            en: docs/grammar-reference.md
            ja: docs/ja/stable-api.md
      YAML
      yield root
    end
  end
end
