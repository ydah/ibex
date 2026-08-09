# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Codegen
    # Generates typed Red syntax views from @node metadata.
    module RubySyntax
      # @rbs!
      #   type syntax_definition = { name: String, kind: Integer, fields: Hash[String, CSTMetadata::field_slot] }

      private

      # @rbs (Array[String] lines) -> void
      def append_syntax(lines)
        # @type self: Ruby
        definitions = syntax_node_definitions
        return if definitions.empty? || !cst?

        lines << "  module Syntax"
        definitions.each_value { |definition| append_syntax_node(lines, definition) }
        lines.push("  end", "")
      end

      # @rbs () -> Hash[String, syntax_definition]
      def syntax_node_definitions
        # @type self: Ruby
        metadata = cst_metadata #: CSTMetadata::metadata
        slots = metadata.fetch(:slots)
        definitions = {} #: Hash[String, syntax_definition]
        @grammar.productions.each do |production|
          node = production.node
          next unless node

          slot = slots.fetch(production.id)
          name = node.fetch(:name)
          previous = definitions[name]
          fields = previous ? merge_syntax_fields(previous.fetch(:fields), slot.fetch(:fields)) : slot.fetch(:fields)
          definitions[name] = { name: name, kind: slot.fetch(:node_kind), fields: fields }.freeze
        end
        definitions
      end

      # @rbs (Hash[String, CSTMetadata::field_slot] left, Hash[String, CSTMetadata::field_slot] right) -> Hash[String, CSTMetadata::field_slot]
      def merge_syntax_fields(left, right)
        left.to_h do |name, left_slot|
          right_slot = right.fetch(name)
          left_index = left_slot.is_a?(Hash) ? left_slot.fetch(:index) : left_slot
          right_index = right_slot.is_a?(Hash) ? right_slot.fetch(:index) : right_slot
          raise Ibex::Error, "inconsistent CST slot for #{name}" unless left_index == right_index

          [name, left_slot == right_slot ? left_slot : left_index]
        end.freeze
      end

      # @rbs (Array[String] lines, syntax_definition definition) -> void
      def append_syntax_node(lines, definition)
        name = definition.fetch(:name)
        fields = definition.fetch(:fields)
        lines.push(
          "    class #{name} < Ibex::Runtime::CST::TypedNode",
          "      KIND = #{definition.fetch(:kind)}",
          "      def self.cast(node) = node.kind == KIND ? new(node) : nil"
        )
        fields.each do |field, slot|
          index = slot.is_a?(Hash) ? slot.fetch(:index) : slot
          lines << "      def #{field} = child_at_slot(#{index})"
        end
        append_repetition_accessors(lines, fields)
        lines.push("    end", "")
      end

      # @rbs (Array[String] lines, Hash[String, CSTMetadata::field_slot] fields) -> void
      def append_repetition_accessors(lines, fields)
        repeated = fields.select { |_field, slot| slot.is_a?(Hash) && slot[:extraction] }
        repeated.each do |field, slot|
          index = slot.fetch(:index)
          separated = slot.fetch(:extraction) == :separated_list
          lines << "      def each_#{field}_element = list_items(#{index}, separated: #{separated})"
          next unless separated

          method = "each_#{field}_separator"
          lines << "      def #{method} = list_items(#{index}, separated: true, separators: true)"
        end
        return unless repeated.one?

        field, slot = repeated.first
        lines << "      alias each_element each_#{field}_element"
        return unless slot.fetch(:extraction) == :separated_list

        lines << "      alias each_separator each_#{field}_separator"
      end
    end
  end
end
