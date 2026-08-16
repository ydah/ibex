# frozen_string_literal: true

require "yaml"
require "pathname"

module Ibex
  module Quality
    # Checks Stable contract markers and the repository's documentation
    # publication/inventory boundaries.
    class DocsCoverage
      ROOT = File.expand_path("../..", __dir__)
      MANIFEST = File.join(ROOT, "docs/registry/stable-features.yml")
      PUBLICATION_MANIFEST = File.join(ROOT, "docs/index.yml")
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
        @manifest = manifest || File.join(@root, "docs/registry/stable-features.yml")
        @publication_manifest = File.join(@root, "docs/index.yml")
      end

      # @rbs () -> void
      def verify!
        document = YAML.safe_load_file(@manifest, permitted_classes: [], aliases: false)
        raise "stable feature manifest must have version 3" unless document["version"] == 3

        features = document.fetch("features")
        raise "stable feature manifest must not be empty" if features.empty?

        features.each { |id, languages| verify_feature(id, languages) }
        verify_cli_documentation
        verify_publication_manifest
        verify_document_inventory
        verify_relative_links
        verify_decisions_index
      end

      private

      # @rbs (String id, Hash[String, untyped] contract) -> void
      def verify_feature(id, contract)
        expected = %w[contract_revision en]
        raise "#{id}: expected contract_revision and en" unless contract.keys.sort == expected

        revision = contract.fetch("contract_revision")
        raise "#{id}: contract_revision must be a positive integer" unless revision.is_a?(Integer) && revision.positive?

        relative_path = contract.fetch("en")
        raise "#{id}: en document path must be a string" unless relative_path.is_a?(String)

        path = File.join(@root, relative_path)
        raise "#{id}: missing en document #{relative_path}" unless File.file?(path)

        marker = "<!-- stable:#{id}:v#{revision} -->"
        markers = File.binread(path).scan(/<!-- stable:#{Regexp.escape(id)}:v\d+ -->/)
        raise "#{id}: #{relative_path} must contain only #{marker} exactly once" unless markers == [marker]
      end

      # @rbs () -> void
      def verify_cli_documentation
        source = [File.binread(File.join(@root, "README.md")),
                  File.binread(File.join(@root, "docs/grammar-reference.md"))].join("\n")
        missing = REQUIRED_CLI_TERMS.reject { |term| source.include?(term) }
        raise "public CLI documentation is missing: #{missing.join(', ')}" unless missing.empty?
      end

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- the manifest gate is intentionally fail-closed.
      def verify_publication_manifest
        manifest = YAML.safe_load_file(@publication_manifest, permitted_classes: [], aliases: false)
        raise "documentation publication manifest must have version 1" unless manifest["version"] == 1

        documents = manifest.fetch("documents")
        slugs = documents.map { |entry| entry.fetch("slug") }
        paths = documents.map { |entry| entry.fetch("path") }
        raise "documentation publication slugs must be unique" unless slugs.uniq == slugs
        raise "documentation publication paths must be unique" unless paths.uniq == paths

        documents.each do |entry|
          relative_path = entry.fetch("path")
          raise "published document must be Markdown: #{relative_path}" unless relative_path.end_with?(".md")

          path = File.join(@root, "docs", relative_path)
          raise "missing published document #{relative_path}" unless File.file?(path)

          verify_front_matter(path, published: true)
        end

        manifest.fetch("assets").each do |entry|
          relative_path = entry.fetch("path")
          path = File.join(@root, "docs", relative_path)
          raise "missing published asset #{relative_path}" unless File.file?(path)
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- inventory validation keeps all inclusion rules visible.
      def verify_document_inventory
        manifest = YAML.safe_load_file(@publication_manifest, permitted_classes: [], aliases: false)
        published = manifest.fetch("documents").map do |entry|
          File.expand_path(File.join(@root, "docs", entry.fetch("path")))
        end
        markdown_files = Dir[File.join(@root, "docs/**/*.md")].map { |path| File.expand_path(path) }

        markdown_files.each do |path|
          next if File.basename(path) == "README.md"
          next if published.include?(path)

          directory_readme = File.join(File.dirname(path), "README.md")
          raise "unpublished document is not indexed: #{relative(path)}" unless File.file?(directory_readme)
        end

        directories = Dir[File.join(@root, "docs/**/")]
        directories.each do |directory|
          files = Dir[File.join(directory, "*.md")].reject { |path| File.basename(path) == "README.md" }
          next if files.length <= 3

          readme = File.join(directory, "README.md")
          unless File.file?(readme)
            raise "documentation directory with more than three documents needs README: #{relative(directory)}"
          end

          source = File.read(readme, encoding: Encoding::UTF_8)
          files.each do |path|
            filename = File.basename(path)
            raise "#{relative(readme)} does not index #{filename}" unless source.include?(filename)
          end
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def verify_relative_links
        markdown_files = Dir[File.join(@root, "docs/**/*.md")]
        markdown_files.each do |path|
          source = File.read(path, encoding: Encoding::UTF_8)
          source.scan(/!?\[[^\]]*\]\(([^)]+)\)/).flatten.each do |href|
            href = href.strip.split(/[[:space:]]+/, 2).first
            next if href.nil? || href.empty? || href.start_with?("#", "http:", "https:", "mailto:")

            target = href.split("#", 2).first
            next if target.empty?

            absolute = File.expand_path(target, File.dirname(path))
            next if File.file?(absolute) || File.directory?(absolute)

            raise "broken documentation link #{relative(path)} -> #{href}"
          end
        end
      end

      def verify_decisions_index
        directory = File.join(@root, "docs/decisions")
        files = Dir[File.join(directory, "*.md")].map { |path| File.basename(path) }
        files = files.reject { |name| name == "README.md" }.sort
        source = File.read(File.join(directory, "README.md"), encoding: Encoding::UTF_8)
        listed = source.scan(/\]\((\d{4}-[^)]+\.md)\)/).flatten.sort
        raise "decisions/README.md must list exactly the current ADRs" unless listed == files
      end

      def verify_front_matter(path, published: false)
        source = File.read(path, encoding: Encoding::UTF_8)
        unless source.start_with?("---\n")
          raise "#{relative(path)} must begin with YAML front matter" if published

          return
        end

        closing = source.lines[1..].index { |line| line.chomp == "---" }
        raise "#{relative(path)} has unterminated YAML front matter" unless closing

        metadata = source.lines[1, closing].each_with_object({}) do |line, result|
          key, value = line.chomp.split(":", 2)
          result[key] = value.to_s.strip unless key.nil? || value.nil?
        end
        %w[title description].each do |key|
          raise "#{relative(path)} front matter is missing #{key}" if metadata[key].to_s.empty?
        end
      end

      def relative(path)
        Pathname(path).relative_path_from(Pathname(@root)).to_s
      end
    end
  end
end
