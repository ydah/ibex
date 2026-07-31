# frozen_string_literal: true

require "yaml"

module Ibex
  module Quality
    # Checks that every Stable contract has synchronized English/Japanese
    # markers and that the v1 analysis CLI remains publicly documented.
    class DocsCoverage
      ROOT = File.expand_path("../..", __dir__)
      MANIFEST = File.join(ROOT, "docs/stable-features.yml")
      REQUIRED_CLI_TERMS = [
        "ibex verify", "ibex equiv", "ibex fix", "ibex diff", "ibex metrics",
        "ibex samples", "ibex fuzz", "ibex reduce", "--lang"
      ].freeze #: Array[String]

      # @rbs () -> void
      def verify!
        document = YAML.safe_load_file(MANIFEST, permitted_classes: [], aliases: false)
        raise "stable feature manifest must have version 1" unless document["version"] == 1

        features = document.fetch("features")
        raise "stable feature manifest must not be empty" if features.empty?

        features.each { |id, languages| verify_feature(id, languages) }
        verify_cli_documentation
      end

      private

      # @rbs (String id, Hash[String, String] languages) -> void
      def verify_feature(id, languages)
        raise "#{id}: expected exactly en and ja documentation" unless languages.keys.sort == %w[en ja]

        languages.each do |language, relative_path|
          path = File.join(ROOT, relative_path)
          raise "#{id}: missing #{language} document #{relative_path}" unless File.file?(path)

          marker = "<!-- stable:#{id} -->"
          count = File.binread(path).scan(marker).length
          raise "#{id}: #{relative_path} must contain #{marker} exactly once" unless count == 1
        end
      end

      # @rbs () -> void
      def verify_cli_documentation
        source = [File.binread(File.join(ROOT, "README.md")),
                  File.binread(File.join(ROOT, "docs/grammar-reference.md"))].join("\n")
        missing = REQUIRED_CLI_TERMS.reject { |term| source.include?(term) }
        raise "public CLI documentation is missing: #{missing.join(', ')}" unless missing.empty?
      end
    end
  end
end
