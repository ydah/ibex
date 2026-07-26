# frozen_string_literal: true

module Ibex
  module Frontend
    # Keeps the public Rule constructor compatible with ASTs built before parameters and inline rules existed.
    module ASTRuleDefaults
      # @rbs (*untyped arguments, **untyped keywords) -> void
      def initialize(*arguments, **keywords)
        if arguments.empty?
          keywords = keywords.merge(parameters: keywords[:parameters] || [], inline: keywords[:inline] || false)
        elsif arguments.one? && arguments.first.is_a?(Hash)
          attributes = arguments.first
          arguments = [
            attributes.merge(parameters: attributes[:parameters] || [], inline: attributes[:inline] || false)
          ]
        end
        super(*arguments, **keywords) # rubocop:disable Style/SuperArguments
      end
    end

    # Grammar frontend node types.
    # rubocop:disable Metrics/ModuleLength -- the public node vocabulary is intentionally kept together.
    module AST
      # @rbs!
      #   type symbol_metadata = DisplayName | SemanticType
      #   type declaration = Include | Tokens | Precedence | Options | Expect | ExpectRR | Start | Convert |
      #     symbol_metadata
      #   type item = SymbolReference | ParameterizedReference | InlineAction | Optional | Star | Plus | Group |
      #     SeparatedList | Empty
      #   type user_code = Hash[String, Array[UserCode]]
      #   class Rule < Struct[String | Array[String] | Array[Alternative] | Location | String? | bool]
      #     attr_accessor lhs: String
      #     attr_accessor parameters: Array[String]
      #     attr_accessor alternatives: Array[Alternative]
      #     attr_accessor loc: Location
      #     attr_accessor documentation: String?
      #     attr_accessor inline: bool
      #     def self.new: (?lhs: String, ?parameters: Array[String]?, ?alternatives: Array[Alternative],
      #       ?loc: Location, ?documentation: String?, ?inline: bool?) -> instance
      #       | ({ ?lhs: String, ?parameters: Array[String]?, ?alternatives: Array[Alternative],
      #         ?loc: Location, ?documentation: String?, ?inline: bool? }) -> instance
      #   end

      # Adds deterministic, recursively serializable hashes to Struct nodes.
      # @rbs module-self Struct[untyped]
      module Node
        def to_h
          fields = each_pair.to_h { |name, value| [name, serialize(value)] }
          fields.delete(:aliases) if self.class.name.end_with?("::Tokens") && !fields[:aliases]
          fields.delete(:extended) if self.class.name.end_with?("::Root") && !fields[:extended]
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
        :extended, #: bool?
        keyword_init: true
      ) { include Node }
      Fragment = Struct.new(
        :declarations, #: Array[declaration]
        :rules, #: Array[Rule]
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Include = Struct.new(
        :path, #: String
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Tokens = Struct.new(
        :names, #: Array[String]
        :aliases, #: Hash[String, String]?
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
      ExpectRR = Struct.new(
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
      # @rbs skip
      Rule = Struct.new(
        :lhs, #: String
        :parameters, #: Array[String]
        :alternatives, #: Array[Alternative]
        :loc, #: Location
        :documentation, #: String?
        :inline, #: bool
        keyword_init: true
      ) { include Node, ASTRuleDefaults }
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
      ParameterizedReference = Struct.new(
        :name, #: String
        :arguments, #: Array[item]
        :named_reference, #: String?
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      InlineAction = Struct.new(
        :code, #: String
        :loc, #: Location
        keyword_init: true
      ) { include Node }
      Empty = Struct.new(
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
    # rubocop:enable Metrics/ModuleLength
  end
end
