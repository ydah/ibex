# frozen_string_literal: true

module Ibex
  module LSP
    # Serves symbol navigation, rename, and hover requests.
    module NavigationHandlers
      include RequestSupport

      private

      # @rbs (untyped raw_params) -> Array[Hash[String, untyped]]
      def definition(raw_params)
        with_index(raw_params) { |index, path, position| index.definition(path, position) }
      end

      # @rbs (untyped raw_params) -> Array[Hash[String, untyped]]
      def references(raw_params)
        params = params_hash(raw_params)
        context = hash_member(params, "context")
        include_declaration = context["includeDeclaration"] == true
        with_index(params) do |index, path, position|
          index.references(path, position, include_declaration: include_declaration)
        end
      end

      # @rbs (untyped raw_params) -> Hash[String, untyped]?
      def prepare_rename(raw_params)
        with_index(raw_params) { |index, path, position| index.prepare_rename(path, position) }
      end

      # @rbs (untyped raw_params) -> Hash[String, untyped]
      def rename(raw_params)
        params = params_hash(raw_params)
        new_name = string_member(params, "newName")
        with_index(params) { |index, path, position| index.rename(path, position, new_name) }
      end

      # @rbs (untyped raw_params) -> Hash[String, untyped]?
      def hover(raw_params)
        with_index(raw_params) { |index, path, position| index.hover(path, position) }
      end

      # @rbs (untyped raw_params) { (SymbolIndex, String, Hash[String, untyped]) -> untyped } -> untyped
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
