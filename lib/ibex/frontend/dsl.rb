# frozen_string_literal: true

module Ibex
  module Frontend
    # Builds the same Grammar AST as the text frontend through a Ruby API.
    module DSL
      # @rbs (class_name: untyped, ?superclass: untyped, ?file: untyped) { (Builder) -> void } -> untyped
      def grammar(class_name:, superclass: nil, file: "(dsl)")
        builder = Builder.new(class_name: class_name, superclass: superclass, file: file)
        yield builder
        builder.to_ast
      end
      module_function :grammar

      # Mutable definition context whose output is an immutable-shape AST.
      class Builder
        def initialize(class_name:, superclass:, file:)
          @class_name = class_name.to_s
          @superclass = superclass&.to_s
          @file = file
          @line = 1
          @declarations = [] #: Array[untyped]
          @rules = [] #: Array[untyped]
          @user_code = Hash.new { |hash, key| hash[key] = Array.new(0) } #: Hash[untyped, Array[untyped]]
        end

        def token(*names)
          @declarations << AST::Tokens.new(names: names.map(&:to_s), loc: next_location)
        end

        def options(*names)
          @declarations << AST::Options.new(names: names.map(&:to_s), loc: next_location)
        end

        def expect(conflicts)
          @declarations << AST::Expect.new(conflicts: conflicts, loc: next_location)
        end

        def start(name)
          @declarations << AST::Start.new(name: name.to_s, loc: next_location)
        end

        def convert(name, expression)
          location = next_location
          pair = AST::Conversion.new(name: name.to_s, expression: expression.to_s, loc: location)
          @declarations << AST::Convert.new(pairs: [pair], loc: location)
        end

        # @rbs (?direction: untyped) { (PrecedenceBuilder) -> void } -> untyped
        def precedence(direction: :low_to_high)
          location = next_location
          builder = PrecedenceBuilder.new(self)
          yield builder
          @declarations << AST::Precedence.new(direction: direction, levels: builder.levels, loc: location)
        end

        # @rbs (untyped lhs) { (RuleBuilder) -> void } -> untyped
        def rule(lhs)
          location = next_location
          builder = RuleBuilder.new(self, location)
          yield builder
          @rules << AST::Rule.new(lhs: lhs.to_s, alternatives: builder.alternatives, loc: location)
        end

        def user_code(name, code)
          key = name.to_s
          @user_code[key] << AST::UserCode.new(name: key, code: code.to_s, loc: next_location)
        end

        def ref(name, as: nil)
          AST::SymbolReference.new(name: name.to_s, named_reference: as&.to_s, loc: next_location)
        end

        def optional(item) = AST::Optional.new(item: normalize_item(item), loc: next_location)
        def star(item) = AST::Star.new(item: normalize_item(item), loc: next_location)
        def plus(item) = AST::Plus.new(item: normalize_item(item), loc: next_location)

        def group(*alternatives)
          normalized = alternatives.map { |alternative| Array(alternative).map { |item| normalize_item(item) } }
          AST::Group.new(alternatives: normalized, loc: next_location)
        end

        def separated_list(item, separator, nonempty: false)
          AST::SeparatedList.new(item: normalize_item(item), separator: normalize_item(separator),
                                 nonempty: nonempty, loc: next_location)
        end

        def inline(code)
          AST::InlineAction.new(code: code.to_s, loc: next_location)
        end

        def to_ast
          location = Location.new(file: @file, line: 1, column: 1)
          AST::Root.new(class_name: @class_name, superclass: @superclass, declarations: @declarations,
                        rules: @rules, user_code: @user_code, loc: location)
        end

        def normalize_item(item)
          return item if item.respond_to?(:loc)

          ref(item)
        end

        def next_location
          location = Location.new(file: @file, line: @line, column: 1)
          @line += 1
          location
        end
      end

      # Collects ordered associativity levels.
      class PrecedenceBuilder
        attr_reader :levels

        def initialize(grammar)
          @grammar = grammar
          @levels = [] #: Array[untyped]
        end

        %i[left right nonassoc].each do |associativity|
          define_method(associativity) do |*symbols|
            @levels << AST::PrecedenceLevel.new(associativity: associativity, symbols: symbols.map(&:to_s),
                                                loc: @grammar.next_location)
          end
        end
      end

      # Collects alternatives for one nonterminal.
      class RuleBuilder
        attr_reader :alternatives

        def initialize(grammar, default_location)
          @grammar = grammar
          @default_location = default_location
          @alternatives = [] #: Array[untyped]
        end

        def alt(*items, action: nil, precedence: nil)
          location = @grammar.next_location || @default_location
          normalized = items.map { |item| @grammar.normalize_item(item) }
          action_node = action && AST::InlineAction.new(code: action.to_s, loc: location)
          alternative = AST::Alternative.new(
            items: normalized, action: action_node, precedence: precedence&.to_s, loc: location
          )
          @alternatives << alternative
        end
      end
    end
  end
end
