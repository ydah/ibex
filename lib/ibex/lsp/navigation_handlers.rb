# frozen_string_literal: true

module Ibex
  module LSP
    # Serves symbol navigation, rename, and hover requests.
    module NavigationHandlers
      include RequestSupport

      private

      # @rbs (lsp_object? raw_params) -> Array[lsp_object]
      def definition(raw_params)
        result = with_index(raw_params) { |index, path, position| index.definition(path, position) } #: Array[lsp_object]
        result
      end

      # @rbs (lsp_object? raw_params) -> Array[lsp_object]
      def references(raw_params)
        params = params_hash(raw_params)
        context = hash_member(params, "context")
        include_declaration = context["includeDeclaration"] == true
        result = with_index(params) do |index, path, position|
          index.references(path, position, include_declaration: include_declaration)
        end #: Array[lsp_object]
        result
      end

      # @rbs (lsp_object? raw_params) -> lsp_object?
      def prepare_rename(raw_params)
        result = with_index(raw_params) { |index, path, position| index.prepare_rename(path, position) } #: lsp_object?
        result
      end

      # @rbs (lsp_object? raw_params) -> lsp_object
      def rename(raw_params)
        params = params_hash(raw_params)
        new_name = string_member(params, "newName")
        result = with_index(params) { |index, path, position| index.rename(path, position, new_name) } #: lsp_object
        result
      end

      # @rbs (lsp_object? raw_params) -> lsp_object?
      def hover(raw_params)
        result = with_index(raw_params) do |index, path, position|
          index.hover(path, position) || ParserConfigurationAssistance.new(store, path).hover(position)
        end #: lsp_object?
        result
      end

      # @rbs (lsp_object? raw_params) -> lsp_object
      def completion(raw_params)
        require_running!
        params = params_hash(raw_params)
        document = hash_member(params, "textDocument")
        path = workspace.path(string_member(document, "uri"))
        position = hash_member(params, "position")
        ParserConfigurationAssistance.new(store, path).completion(position)
      rescue ArgumentError => e
        raise ProtocolError.new(e.message, code: -32_602)
      end

      # @rbs (lsp_object? raw_params) { (SymbolIndex, String, lsp_object) -> Object? } -> Object?
      def with_index(raw_params)
        require_running!
        params = params_hash(raw_params)
        document = hash_member(params, "textDocument")
        path = workspace.path(string_member(document, "uri"))
        position = hash_member(params, "position")
        yield SymbolIndex.new(store, path), path, position
      rescue ArgumentError => e
        raise ProtocolError.new(e.message, code: -32_602)
      end
    end
  end
end
