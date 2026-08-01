# frozen_string_literal: true

require "yaml"

module Ibex
  module Quality
    # Checks that every Stable contract has the same reviewed revision in its
    # English and Japanese documents and that the analysis CLI is public.
    class DocsCoverage
      ROOT = File.expand_path("../..", __dir__)
      MANIFEST = File.join(ROOT, "docs/stable-features.yml")
      REQUIRED_CLI_TERMS = [
        "ibex verify", "ibex equiv", "ibex fix", "ibex diff", "ibex metrics",
        "ibex samples", "ibex fuzz", "ibex reduce", "ibex import bison",
        "--against-runtime", "--against-timeout", "--against-max-output",
        "--max-reduction-trials", "--timeout", "--max-output-bytes",
        "--max-input-bytes", "--regression-dir", "--lang"
      ].freeze #: Array[String]

      # @rbs (?root: String, ?manifest: String?) -> void
      def initialize(root: ROOT, manifest: nil)
        @root = File.expand_path(root)
        @manifest = manifest || File.join(@root, "docs/stable-features.yml")
      end

      # @rbs () -> void
      def verify!
        document = YAML.safe_load_file(@manifest, permitted_classes: [], aliases: false)
        raise "stable feature manifest must have version 2" unless document["version"] == 2

        features = document.fetch("features")
        raise "stable feature manifest must not be empty" if features.empty?

        features.each { |id, languages| verify_feature(id, languages) }
        verify_cli_documentation
      end

      private

      # @rbs (String id, Hash[String, untyped] contract) -> void
      def verify_feature(id, contract)
        expected = %w[contract_revision en ja]
        raise "#{id}: expected contract_revision, en, and ja" unless contract.keys.sort == expected

        revision = contract.fetch("contract_revision")
        raise "#{id}: contract_revision must be a positive integer" unless revision.is_a?(Integer) && revision.positive?

        %w[en ja].each do |language|
          relative_path = contract.fetch(language)
          raise "#{id}: #{language} document path must be a string" unless relative_path.is_a?(String)

          path = File.join(@root, relative_path)
          raise "#{id}: missing #{language} document #{relative_path}" unless File.file?(path)

          marker = "<!-- stable:#{id}:v#{revision} -->"
          markers = File.binread(path).scan(/<!-- stable:#{Regexp.escape(id)}:v\d+ -->/)
          raise "#{id}: #{relative_path} must contain only #{marker} exactly once" unless markers == [marker]
        end
      end

      # @rbs () -> void
      def verify_cli_documentation
        source = [File.binread(File.join(@root, "README.md")),
                  File.binread(File.join(@root, "docs/grammar-reference.md"))].join("\n")
        missing = REQUIRED_CLI_TERMS.reject { |term| source.include?(term) }
        raise "public CLI documentation is missing: #{missing.join(', ')}" unless missing.empty?
      end
    end
  end
end
