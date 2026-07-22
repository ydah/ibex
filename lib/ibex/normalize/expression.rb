# frozen_string_literal: true

module Ibex
  # Deterministically renders frontend EBNF items for production origin metadata.
  module NormalizeExpression
    # @rbs!
    #   private def render_reference: (Frontend::AST::SymbolReference item) -> String
    #   private def self.render_reference: (Frontend::AST::SymbolReference item) -> String
    #   private def render_group: (Frontend::AST::Group item) -> String
    #   private def self.render_group: (Frontend::AST::Group item) -> String
    #   private def render_separated_list: (Frontend::AST::SeparatedList item) -> String
    #   private def self.render_separated_list: (Frontend::AST::SeparatedList item) -> String

    # @rbs (Frontend::AST::item item) -> String
    def render(item)
      case item
      when Frontend::AST::SymbolReference then render_reference(item)
      when Frontend::AST::Group then render_group(item)
      when Frontend::AST::Optional then "#{render(item.item)}?"
      when Frontend::AST::Star then "#{render(item.item)}*"
      when Frontend::AST::Plus then "#{render(item.item)}+"
      when Frontend::AST::SeparatedList then render_separated_list(item)
      else raise Ibex::Error, "#{item.loc}: cannot render unsupported EBNF expression"
      end
    end
    module_function :render

    # @rbs skip
    private

    # @rbs skip
    def render_reference(item)
      suffix = item.named_reference ? ":#{item.named_reference}" : ""
      "#{item.name}#{suffix}"
    end

    # @rbs skip
    def render_group(item)
      alternatives = item.alternatives.map { |items| items.map { |child| render(child) }.join(" ") }
      "(#{alternatives.join(' | ')})"
    end

    # @rbs skip
    def render_separated_list(item)
      name = item.nonempty ? "separated_nonempty_list" : "separated_list"
      "#{name}(#{render(item.item)}, #{render(item.separator)})"
    end
    module_function :render_reference, :render_group, :render_separated_list

    class << self
      private :render_reference, :render_group, :render_separated_list
    end
  end
end
