# frozen_string_literal: true

module Ibex
  module Frontend
    # Semantic builders for fragment and include frontend nodes.
    module GeneratedParserIncludes
      private

      # @rbs (Token keyword, Array[AST::declaration] declarations, Array[AST::Rule] rules,
      #   AST::user_code user_code) -> AST::Fragment
      def build_fragment(keyword, declarations, rules, user_code)
        # @type self: GeneratedParserBase
        extended_only!(keyword.location, "fragments")
        reject_fragment_root_declarations(declarations)
        user_block = user_code.values.flatten.first
        fail_at(user_block.loc, "user code is not allowed in fragments") if user_block
        AST::Fragment.new(declarations: declarations, rules: rules, loc: keyword.location)
      end

      # @rbs (Token keyword, Token path) -> AST::Include
      def build_include(keyword, path)
        # @type self: GeneratedParserBase
        label = token_string(keyword)
        extended_only!(keyword.location, "#{label}s")
        value = token_string(path)
        unless value.start_with?('"') && value.end_with?('"')
          fail_at(path.location, "#{label} path must use a double-quoted string")
        end

        AST::Include.new(path: value.undump, loc: keyword.location)
      rescue RuntimeError => e
        fail_at(path.location, "invalid #{label} path: #{e.message}")
      end

      # @rbs (Array[AST::declaration] declarations) -> void
      def reject_fragment_root_declarations(declarations)
        # @type self: GeneratedParserBase
        root_only = declarations.find { |declaration| fragment_root_declaration_name(declaration) }
        return unless root_only

        name = fragment_root_declaration_name(root_only)
        fail_at(root_only.loc, "#{name} declarations are not allowed in fragments")
      end

      # @rbs (AST::declaration declaration) -> String?
      def fragment_root_declaration_name(declaration)
        AST::ROOT_ONLY_DECLARATION_NAMES.find { |node_class, _name| declaration.is_a?(node_class) }&.last
      end
    end
  end
end
