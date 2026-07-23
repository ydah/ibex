# frozen_string_literal: true

module Ibex
  module Frontend
    # Builds the same Grammar AST as the text frontend through a Ruby API.
    module DSL
      # @rbs (class_name: Object, ?superclass: Object?, ?file: String) { (Builder) -> void } -> AST::Root
      def grammar(class_name:, superclass: nil, file: "(dsl)")
        builder = Builder.new(class_name: class_name, superclass: superclass, file: file)
        yield builder
        builder.to_ast
      end
      module_function :grammar

      # Mutable definition context whose output is an immutable-shape AST.
      class Builder
        # @rbs @class_name: String
        # @rbs @superclass: String?
        # @rbs @file: String
        # @rbs @line: Integer
        # @rbs @declarations: Array[AST::declaration]
        # @rbs @rules: Array[AST::Rule]
        # @rbs @user_code: AST::user_code

        # @rbs (class_name: Object, superclass: Object?, file: String) -> void
        def initialize(class_name:, superclass:, file:)
          @class_name = class_name.to_s
          @superclass = superclass&.to_s
          @file = file
          @line = 1
          @declarations = [] #: Array[AST::declaration]
          @rules = [] #: Array[AST::Rule]
          @user_code = Hash.new { |hash, key| hash[key] = Array.new(0) } #: AST::user_code
        end

        # @rbs (*Object names) -> void
        def token(*names)
          @declarations << AST::Tokens.new(names: names.map(&:to_s), loc: next_location)
        end

        # @rbs (*Object names) -> void
        def options(*names)
          @declarations << AST::Options.new(names: names.map(&:to_s), loc: next_location)
        end

        # @rbs (Integer conflicts) -> void
        def expect(conflicts)
          @declarations << AST::Expect.new(conflicts: conflicts, loc: next_location)
        end

        # @rbs (Object name) -> void
        def start(name)
          @declarations << AST::Start.new(name: name.to_s, loc: next_location)
        end

        # @rbs (Object name, Object expression) -> void
        def convert(name, expression)
          location = next_location
          pair = AST::Conversion.new(name: name.to_s, expression: expression.to_s, loc: location)
          @declarations << AST::Convert.new(pairs: [pair], loc: location)
        end

        # @rbs (Object name, Object value) -> void
        def display(name, value)
          @declarations << AST::DisplayName.new(name: name.to_s, value: metadata_value(value, "display"),
                                                loc: next_location)
        end

        # @rbs (Object name, Object value) -> void
        def type(name, value)
          @declarations << AST::SemanticType.new(name: name.to_s, value: metadata_value(value, "type"),
                                                 loc: next_location)
        end

        # @rbs (?direction: Symbol) { (PrecedenceBuilder) -> void } -> void
        def precedence(direction: :low_to_high)
          location = next_location
          builder = PrecedenceBuilder.new(self)
          yield builder
          @declarations << AST::Precedence.new(direction: direction, levels: builder.levels, loc: location)
        end

        # @rbs (Object lhs) { (RuleBuilder) -> void } -> void
        def rule(lhs)
          location = next_location
          builder = RuleBuilder.new(self, location)
          yield builder
          @rules << AST::Rule.new(lhs: lhs.to_s, alternatives: builder.alternatives, loc: location)
        end

        # @rbs (Object name, Object code) -> void
        def user_code(name, code)
          key = name.to_s
          @user_code[key] << AST::UserCode.new(name: key, code: code.to_s, loc: next_location)
        end

        # @rbs (Object name, ?as: Object?) -> AST::SymbolReference
        def ref(name, as: nil)
          AST::SymbolReference.new(name: name.to_s, named_reference: as&.to_s, loc: next_location)
        end

        # @rbs (Object item) -> AST::Optional
        def optional(item) = AST::Optional.new(item: normalize_item(item), loc: next_location)
        # @rbs (Object item) -> AST::Star
        def star(item) = AST::Star.new(item: normalize_item(item), loc: next_location)
        # @rbs (Object item) -> AST::Plus
        def plus(item) = AST::Plus.new(item: normalize_item(item), loc: next_location)

        # @rbs (*Object alternatives) -> AST::Group
        def group(*alternatives)
          normalized = alternatives.map { |alternative| Array(alternative).map { |item| normalize_item(item) } }
          AST::Group.new(alternatives: normalized, loc: next_location)
        end

        # @rbs (Object item, Object separator, ?nonempty: bool) -> AST::SeparatedList
        def separated_list(item, separator, nonempty: false)
          AST::SeparatedList.new(item: normalize_item(item), separator: normalize_item(separator),
                                 nonempty: nonempty, loc: next_location)
        end

        # @rbs (Object code) -> AST::InlineAction
        def inline(code)
          AST::InlineAction.new(code: code.to_s, loc: next_location)
        end

        # @rbs () -> AST::Root
        def to_ast
          location = Location.new(file: @file, line: 1, column: 1)
          AST::Root.new(class_name: @class_name, superclass: @superclass, declarations: @declarations,
                        rules: @rules, user_code: @user_code, loc: location)
        end

        # @rbs (Object item) -> AST::item
        def normalize_item(item)
          if item.respond_to?(:loc)
            located_item = item #: AST::item
            return located_item
          end

          ref(item)
        end

        # @rbs () -> Location
        def next_location
          location = Location.new(file: @file, line: @line, column: 1)
          @line += 1
          location
        end

        private

        # @rbs (Object value, String feature) -> String
        def metadata_value(value, feature)
          string = value.to_s
          raise ArgumentError, "#{feature} value must not be empty" if string.strip.empty?
          raise ArgumentError, "#{feature} value must be a single line" if string.match?(/[\r\n]/)
          raise ArgumentError, "#{feature} value must not contain control characters" if
            string.match?(/[[:cntrl:]]/)

          string
        end
      end

      # Collects ordered associativity levels.
      class PrecedenceBuilder
        attr_reader :levels #: Array[AST::PrecedenceLevel]

        # @rbs @grammar: Builder

        # @rbs (Builder grammar) -> void
        def initialize(grammar)
          @grammar = grammar
          @levels = [] #: Array[AST::PrecedenceLevel]
        end

        # @rbs (*Object symbols) -> void
        def left(*symbols) = add_level(:left, symbols)

        # @rbs (*Object symbols) -> void
        def right(*symbols) = add_level(:right, symbols)

        # @rbs (*Object symbols) -> void
        def nonassoc(*symbols) = add_level(:nonassoc, symbols)

        private

        # @rbs (Symbol associativity, Array[Object] symbols) -> void
        def add_level(associativity, symbols)
          @levels << AST::PrecedenceLevel.new(associativity: associativity, symbols: symbols.map(&:to_s),
                                              loc: @grammar.next_location)
        end
      end

      # Collects alternatives for one nonterminal.
      class RuleBuilder
        attr_reader :alternatives #: Array[AST::Alternative]

        # @rbs @grammar: Builder
        # @rbs @default_location: Location

        # @rbs (Builder grammar, Location default_location) -> void
        def initialize(grammar, default_location)
          @grammar = grammar
          @default_location = default_location
          @alternatives = [] #: Array[AST::Alternative]
        end

        # @rbs (*Object items, ?action: Object?, ?precedence: Object?) -> void
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
