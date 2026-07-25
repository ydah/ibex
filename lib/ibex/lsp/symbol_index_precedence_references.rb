# frozen_string_literal: true

module Ibex
  module LSP
    # Indexes rule-scoped item and alternative precedence references.
    module SymbolIndexPrecedenceReferences
      private

      # @rbs (String path, Frontend::SourceDocument document, Frontend::AST::Alternative alternative,
      #   Frontend::Location? following, Frontend::AST::Rule rule, Integer rule_id) -> void
      def collect_alternative_precedence(path, document, alternative, following, rule, rule_id)
        # @type self: SymbolIndexBuilder
        name = alternative.precedence
        return unless name

        tokens = tokens_between(document, alternative.loc, following)
        index = (0...(tokens.length - 1)).to_a.reverse.find do |candidate|
          tokens.fetch(candidate).value == "=" && tokens.fetch(candidate + 1).value == name
        end
        token = index && tokens[index + 1]
        add_rule_reference(path, token, name, rule, rule_id) if token
      end

      # @rbs (String path, Frontend::Token token, String name, Frontend::AST::Rule rule,
      #   Integer rule_id) -> void
      def add_rule_reference(path, token, name, rule, rule_id)
        # @type self: SymbolIndexBuilder
        return unless token.span

        if rule.parameters.include?(name)
          key = parameter_key(path, rule_id, name)
          kind = :parameter
          data = { rule: rule.lhs }
        else
          key = global_key(name)
          kind = @global_kinds[name] || :rule
          data = symbol_data(kind, name)
        end
        add_occurrence(name: name, kind: kind, role: :reference, key: key,
                       path: path, span: token.span, data: data)
      end
    end
  end
end
