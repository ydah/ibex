# frozen_string_literal: true

module Ibex
  # Deterministically renders frontend EBNF items for production origin metadata.
  module NormalizeExpression
    # @rbs! type pending_item = String | Frontend::AST::item

    class << self
      # @rbs (Frontend::AST::item item) -> String
      def render(item)
        pending = [item] #: Array[pending_item]
        output = [] #: Array[String]
        until pending.empty?
          current = pending.pop
          if current.is_a?(String)
            output << current
            next
          end

          push_render_item(pending, current)
        end
        output.join
      end

      private

      # @rbs (Array[pending_item] pending, Frontend::AST::item item) -> void
      def push_render_item(pending, item)
        case item
        when Frontend::AST::SymbolReference
          pending << "#{item.name}#{":#{item.named_reference}" if item.named_reference}"
        when Frontend::AST::ParameterizedReference
          push_render_parameterized_reference(pending, item)
        when Frontend::AST::Group
          push_render_group(pending, item)
        when Frontend::AST::Optional
          pending.push("?", item.item)
        when Frontend::AST::Star
          pending.push("*", item.item)
        when Frontend::AST::Plus
          pending.push("+", item.item)
        when Frontend::AST::SeparatedList
          name = item.nonempty ? "separated_nonempty_list" : "separated_list"
          pending.push(")", item.separator, ", ", item.item, "(", name)
        else
          raise Ibex::Error, "#{item.loc}: cannot render unsupported EBNF expression"
        end
      end

      # @rbs (Array[pending_item] pending, Frontend::AST::ParameterizedReference item) -> void
      def push_render_parameterized_reference(pending, item)
        pending << ":#{item.named_reference}" if item.named_reference
        pending << ")"
        push_render_items(pending, item.arguments, ", ")
        pending.push("(", item.name)
      end

      # @rbs (Array[pending_item] pending, Frontend::AST::Group item) -> void
      def push_render_group(pending, item)
        pending << ")"
        (item.alternatives.length - 1).downto(0) do |index|
          pending << " | " if index < item.alternatives.length - 1
          push_render_items(pending, item.alternatives.fetch(index), " ")
        end
        pending << "("
      end

      # @rbs (Array[pending_item] pending, Array[Frontend::AST::item] items, String separator) -> void
      def push_render_items(pending, items, separator)
        (items.length - 1).downto(0) do |index|
          pending << separator if index < items.length - 1
          pending << items.fetch(index)
        end
      end
    end
  end
end
