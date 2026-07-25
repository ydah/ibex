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
        extended_only!(keyword.location, "includes")
        value = token_string(path)
        unless value.start_with?('"') && value.end_with?('"')
          fail_at(path.location, "include path must use a double-quoted string")
        end

        AST::Include.new(path: value.undump, loc: keyword.location)
      rescue RuntimeError => e
        fail_at(path.location, "invalid include path: #{e.message}")
      end

      # @rbs (Array[AST::declaration] declarations) -> void
      def reject_fragment_root_declarations(declarations)
        # @type self: GeneratedParserBase
        root_only = declarations.find do |declaration|
          declaration.is_a?(AST::Options) || declaration.is_a?(AST::Expect) || declaration.is_a?(AST::Start)
        end
        return unless root_only

        name = case root_only
               when AST::Options then "options"
               when AST::Expect then "expect"
               else "start"
               end
        fail_at(root_only.loc, "#{name} declarations are not allowed in fragments")
      end
    end
  end
end
