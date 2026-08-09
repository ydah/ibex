# frozen_string_literal: true

module Ibex
  module LSP
    # Parses workspace sources, discovers safe include closures, and renders diagnostics.
    class WorkspaceAnalyzer
      GLOB_CHARACTERS = /[*?\[\]{}]/ #: Regexp
      WINDOWS_ABSOLUTE = %r{\A(?:[A-Za-z]:[\\/]|\\\\)} #: Regexp

      # @rbs!
      #   type lsp_diagnostic = lsp_object
      #   type analyzed_document = {
      #     source: String,
      #     document: Frontend::SourceDocument?,
      #     diagnostics: Array[lsp_diagnostic]
      #   }

      # @rbs (Workspace workspace, Frontend::SourceLoader loader) -> void
      def initialize(workspace, loader)
        @workspace = workspace
        @loader = loader
      end

      # @rbs (String path) -> analyzed_document
      def analyze(path)
        source = @loader.read(path)
        return analyze_fragment(path, source) if fragment_source?(source, path)

        analyze_root(path, source)
      rescue Ibex::Error, SystemCallError => e
        source ||= readable_source(path)
        { source: source, document: nil, diagnostics: [diagnostic(e.message, source, path)] }
      end

      # @rbs (String root) -> [Array[String], Hash[String, analyzed_document]]
      def closure(root)
        files = [] #: Array[String]
        analyzed = {} #: Hash[String, analyzed_document]
        visiting = [root]
        until visiting.empty?
          path = visiting.pop
          next unless path
          next if analyzed.key?(path)

          current = analyze(path)
          analyzed[path] = current
          files << path
          dependencies(current.fetch(:document)).reverse_each do |target|
            visiting << target unless analyzed.key?(target)
          end
        end
        [files, analyzed]
      end

      # @rbs (String root) -> [Frontend::Resolution?, Array[lsp_diagnostic]]
      def resolve(root)
        resolution = Frontend::Resolver.new(root, mode: :extended, loader: @loader).resolve
        [resolution, []]
      rescue Ibex::Error, SystemCallError => e
        [nil, [diagnostic(e.message, source_for_error(e.message, root), file_for_error(e.message, root))]]
      end

      private

      # @rbs (String path, String source) -> analyzed_document
      def analyze_root(path, source)
        result = Frontend::Parser.new(source, file: path, mode: :extended)
                                 .parse_with_diagnostics(max_diagnostics: 20)
        diagnostics = result.diagnostics.map { |entry| frontend_diagnostic(entry, source) }
        { source: source, document: result.document, diagnostics: diagnostics }
      end

      # @rbs (String path, String source) -> analyzed_document
      def analyze_fragment(path, source)
        document = Frontend::Parser.new(source, file: path, mode: :extended).parse_source_document
        { source: source, document: document, diagnostics: [] }
      end

      # @rbs (String source, String path) -> bool
      def fragment_source?(source, path)
        document, = Frontend::Lexer.new(source, file: path).tokenize_document_recovering(max_diagnostics: 1)
        first = document.tokens.find { |token| token.type != :eof }
        first&.value == "fragment"
      rescue Ibex::Error
        false
      end

      # @rbs (Frontend::SourceDocument? document) -> Array[String]
      def dependencies(document)
        ast = document&.ast
        return [] unless ast

        ast.declarations.filter_map do |declaration|
          next unless declaration.is_a?(Frontend::AST::Include)

          canonical_include(declaration)
        rescue Ibex::Error, SystemCallError
          nil
        end
      end

      # @rbs (Frontend::AST::Include include_node) -> String
      def canonical_include(include_node)
        path = include_node.path
        return invalid_include(include_node) if path.empty? || path.include?("\0")
        return invalid_include(include_node) if path.start_with?("/") || path.match?(WINDOWS_ABSOLUTE)
        return invalid_include(include_node) if path.split(%r{[\\/]}).include?("..")
        return invalid_include(include_node) if path.match?(GLOB_CHARACTERS)

        candidate = File.expand_path(path, File.dirname(include_node.loc.file))
        canonical = @loader.canonical_path(candidate, allow_missing: true)
        return canonical if @workspace.root_for(canonical)

        invalid_include(include_node)
      end

      # @rbs (Frontend::AST::Include include_node) -> bot
      def invalid_include(include_node)
        raise Ibex::Error, "#{include_node.loc}: unsafe include path"
      end

      # @rbs (String message, String source, String fallback_path) -> lsp_diagnostic
      def diagnostic(message, source, fallback_path)
        file, line, column, text = diagnostic_parts(message, fallback_path)
        {
          "range" => diagnostic_range(source, line, column),
          "severity" => 1,
          "code" => "ibex.frontend",
          "source" => "ibex",
          "message" => text,
          "data" => { "file" => file }
        }
      end

      # @rbs (Frontend::Diagnostic diagnostic, String source) -> lsp_diagnostic
      def frontend_diagnostic(diagnostic, source)
        range = if diagnostic.span
                  PositionCodec.new(source).range(diagnostic.span)
                else
                  diagnostic_range(source, diagnostic.location.line, diagnostic.location.column)
                end
        {
          "range" => range,
          "severity" => 1,
          "code" => diagnostic.code,
          "source" => "ibex",
          "message" => diagnostic.message,
          "data" => { "file" => diagnostic.location.file }
        }
      rescue ArgumentError, Ibex::Error
        {
          "range" => diagnostic_range("", 1, 1),
          "severity" => 1,
          "code" => diagnostic.code,
          "source" => "ibex",
          "message" => diagnostic.message,
          "data" => { "file" => diagnostic.location.file }
        }
      end

      # @rbs (String message, String fallback_path) -> [String, Integer, Integer, String]
      def diagnostic_parts(message, fallback_path)
        match = message.match(/\A(.*):(\d+):(\d+):\s*(.*)\z/m)
        return [fallback_path, 1, 1, message] unless match

        [match[1] || fallback_path, Integer(match[2]), Integer(match[3]), match[4] || message]
      end

      # @rbs (String source, Integer line, Integer column) -> Hash[String, Hash[String, Integer]]
      def diagnostic_range(source, line, column)
        line_text = source.lines.fetch(line - 1, "").delete_suffix("\n").delete_suffix("\r")
        prefix = line_text.each_char.take([column - 1, 0].max).join
        character = prefix.each_codepoint.sum { |codepoint| codepoint > 0xFFFF ? 2 : 1 }
        point = { "line" => [line - 1, 0].max, "character" => character }
        { "start" => point, "end" => point.dup }
      end

      # @rbs (String path) -> String
      def readable_source(path)
        @loader.read(path)
      rescue SystemCallError
        ""
      end

      # @rbs (String message, String fallback) -> String
      def file_for_error(message, fallback)
        match = message.match(/\A(.*):\d+:\d+:/)
        return fallback unless match

        match[1] || fallback
      end

      # @rbs (String message, String fallback) -> String
      def source_for_error(message, fallback)
        readable_source(file_for_error(message, fallback))
      end
    end
  end
end
