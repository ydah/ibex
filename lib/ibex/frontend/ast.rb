# frozen_string_literal: true

module Ibex
  module Frontend
    # Grammar frontend node types.
    module AST
      # @rbs!
      #   type symbol_metadata = DisplayName | SemanticType
      #   type declaration = Tokens | Precedence | Options | Expect | Start | Convert | symbol_metadata
      #   type item = SymbolReference | InlineAction | Optional | Star | Plus | Group | SeparatedList
      #   type user_code = Hash[String, Array[UserCode]]

      # Adds deterministic, recursively serializable hashes to Struct nodes.
      # @rbs module-self Struct[untyped]
      module Node
        def to_h
          fields = each_pair.to_h { |name, value| [name, serialize(value)] }
          { node: self.class.name.split("::").last }.merge(fields)
        end

        private

        def serialize(value)
          return value if value.nil?

          case value
          when Array then value.map { |item| serialize(item) }
          when Hash then value.to_h { |key, item| [key, serialize(item)] }
          else value.respond_to?(:to_h) ? value.to_h : value
          end
        end
      end

      Root = Struct.new(
        :class_name, #: String
        :superclass, #: String?
        :declarations, #: Array[declaration]
        :rules, #: Array[Rule]
        :user_code, #: user_code
        :loc, #: Location
        keyword_init: true
      ) do
        include Node
      end
      Tokens = Struct.new(
        :names, #: Array[String]
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Precedence = Struct.new(
        :direction, #: Symbol
        :levels, #: Array[PrecedenceLevel]
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      PrecedenceLevel = Struct.new(
        :associativity, #: Symbol
        :symbols, #: Array[String]
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Options = Struct.new(
        :names, #: Array[String]
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Expect = Struct.new(
        :conflicts, #: Integer
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Start = Struct.new(
        :name, #: String
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Convert = Struct.new(
        :pairs, #: Array[Conversion]
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Conversion = Struct.new(
        :name, #: String
        :expression, #: String
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      DisplayName = Struct.new(
        :name, #: String
        :value, #: String
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      SemanticType = Struct.new(
        :name, #: String
        :value, #: String
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Rule = Struct.new(
        :lhs, #: String
        :alternatives, #: Array[Alternative]
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Alternative = Struct.new(
        :items, #: Array[item]
        :action, #: InlineAction?
        :precedence, #: String?
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      SymbolReference = Struct.new(
        :name, #: String
        :named_reference, #: String?
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      InlineAction = Struct.new(
        :code, #: String
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Optional = Struct.new(
        :item, #: item
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Star = Struct.new(
        :item, #: item
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Plus = Struct.new(
        :item, #: item
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Group = Struct.new(
        :alternatives, #: Array[Array[item]]
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      SeparatedList = Struct.new(
        :item, #: item
        :separator, #: item
        :nonempty, #: bool
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      UserCode = Struct.new(
        :name, #: String
        :code, #: String
        :loc, #: Location
        keyword_init: true
      ) { include Node }
    end
  end
end
