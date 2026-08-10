# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # Assembles the installed runtime into one dependency-free Ruby source.
    module EmbeddedSource
      FILES = %w[
        version.rb
        table_format.rb
        location_span.rb
        cst/kind.rb
        cst/annotation.rb
        cst/green/trivia.rb
        cst/green/token.rb
        cst/green/node.rb
        cst/green/cache.rb
        cst/green/builder.rb
        cst/source_text.rb
        cst/syntax_token.rb
        cst/syntax_node.rb
        cst/cursor.rb
        cst/typed_node.rb
        cst/parse_result.rb
        cst/editing.rb
        cst/text_edit.rb
        cst/rewriter.rb
        cst/editor.rb
        cst/diff.rb
        cst/serialized_tree.rb
        cst/validator.rb
        cst/serialize.rb
        cst/incremental/token_memo.rb
        cst/incremental/relexer.rb
        cst/incremental/parse_memo.rb
        cst/incremental/lexed_syntax.rb
        cst/incremental/blender.rb
        cst/incremental/session.rb
        cst.rb
        ast_data.rb
        resource_limits.rb
        event_sanitizer.rb
        syntax_session.rb
        event.rb
        observation.rb
        repair.rb
        repair_priority_queue.rb
        repair_search.rb
        syntax_repair.rb
        parser_sync_recovery.rb
        parser.rb
        lexer_input.rb
        generated_lexer.rb
        event_jsonl_tracer.rb
        ../tables/compact.rb
        ../tables/compact_actions.rb
        ../tables/compact_productions.rb
      ].freeze #: Array[String]
      REQUIRE_RELATIVE = /^\s*require_relative\s+["']([^"']+)["']/
      private_constant :FILES, :REQUIRE_RELATIVE

      # @rbs () -> String
      def self.render
        paths = FILES.map { |relative_path| File.expand_path(relative_path, File.dirname(__FILE__)) }
        validate_manifest!(paths)
        paths.map { |path| source(path) }.join("\n")
      end

      # @rbs (Array[String] paths) -> void
      def self.validate_manifest!(paths)
        raise "embedded runtime manifest contains duplicate files" unless paths.uniq.length == paths.length

        positions = paths.each_with_index.to_h
        paths.each_with_index do |path, position|
          raise "embedded runtime source is missing: #{path}" unless File.file?(path)

          File.foreach(path) do |line|
            match = REQUIRE_RELATIVE.match(line)
            next unless match

            dependency = File.expand_path("#{match[1]}.rb", File.dirname(path))
            dependency_position = positions[dependency]
            next if dependency_position && dependency_position < position

            raise "embedded runtime dependency must precede #{path}: #{dependency}"
          end
        end
      end
      private_class_method :validate_manifest!

      # @rbs (String path) -> String
      def self.source(path)
        File.read(path).lines.reject { |line| line.start_with?("# frozen_string_literal:") }.join.rstrip
      end
      private_class_method :source
    end
  end
end
