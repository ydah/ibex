# frozen_string_literal: true

module Ibex
  module Frontend
    # Grammar frontend node types.
    module AST
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

      Root = Struct.new(:class_name, :superclass, :declarations, :rules, :user_code, :loc, keyword_init: true) do
        include Node
      end
      Tokens = Struct.new(:names, :loc, keyword_init: true) { include Node }
      Precedence = Struct.new(:direction, :levels, :loc, keyword_init: true) { include Node }
      PrecedenceLevel = Struct.new(:associativity, :symbols, :loc, keyword_init: true) { include Node }
      Options = Struct.new(:names, :loc, keyword_init: true) { include Node }
      Expect = Struct.new(:conflicts, :loc, keyword_init: true) { include Node }
      Start = Struct.new(:name, :loc, keyword_init: true) { include Node }
      Convert = Struct.new(:pairs, :loc, keyword_init: true) { include Node }
      Conversion = Struct.new(:name, :expression, :loc, keyword_init: true) { include Node }
      Rule = Struct.new(:lhs, :alternatives, :loc, keyword_init: true) { include Node }
      Alternative = Struct.new(:items, :action, :precedence, :loc, keyword_init: true) { include Node }
      SymbolReference = Struct.new(:name, :named_reference, :loc, keyword_init: true) { include Node }
      InlineAction = Struct.new(:code, :loc, keyword_init: true) { include Node }
      Optional = Struct.new(:item, :loc, keyword_init: true) { include Node }
      Star = Struct.new(:item, :loc, keyword_init: true) { include Node }
      Plus = Struct.new(:item, :loc, keyword_init: true) { include Node }
      Group = Struct.new(:alternatives, :loc, keyword_init: true) { include Node }
      SeparatedList = Struct.new(:item, :separator, :nonempty, :loc, keyword_init: true) { include Node }
      UserCode = Struct.new(:name, :code, :loc, keyword_init: true) { include Node }
    end
  end
end
