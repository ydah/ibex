# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Codegen
    # Generates typed AST data classes and traversal bases from @node metadata.
    module RubyAST
      private

      # @rbs (Array[String] lines) -> void
      def append_ast(lines)
        definitions = ast_node_definitions
        return if definitions.empty?

        lines << "  module AST"
        definitions.each_value do |node|
          members = node.fetch(:fields).map { |field| ":#{field}" }.join(", ")
          lines << "    #{node.fetch(:name)} = Ibex::Runtime::ASTData.define(#{members})"
        end
        lines << ""
        append_visitor(lines, definitions)
        lines << ""
        append_listener(lines, definitions)
        lines.push("  end", "")
      end

      # @rbs () -> Hash[String, IR::node_annotation]
      def ast_node_definitions
        @grammar.productions.filter_map(&:node).to_h { |node| [node.fetch(:name), node] }
      end

      # @rbs (Array[String] lines, Hash[String, IR::node_annotation] definitions) -> void
      def append_visitor(lines, definitions)
        lines.push("    class Visitor", "      def visit(node)", "        case node")
        definitions.each_value do |node|
          lines << "        when #{node.fetch(:name)} then visit_#{ast_method_name(node.fetch(:name))}(node)"
        end
        lines.push("        else visit_children(node)", "        end", "      end", "")
        definitions.each_value do |node|
          method = ast_method_name(node.fetch(:name))
          lines.push("      def visit_#{method}(node)", "        visit_children(node)", "      end", "")
        end
        append_visit_children(lines)
        lines << "    end"
      end

      # @rbs (Array[String] lines) -> void
      def append_visit_children(lines)
        lines.push(
          "      def visit_children(node)",
          "        children = if node.is_a?(Array)",
          "                     node",
          "                   elsif node.respond_to?(:deconstruct)",
          "                     node.deconstruct",
          "                   else",
          "                     []",
          "                   end",
          "        children.each { |child| visit(child) }",
          "        node",
          "      end"
        )
      end

      # @rbs (Array[String] lines, Hash[String, IR::node_annotation] definitions) -> void
      def append_listener(lines, definitions)
        lines.push("    class Listener", "      def walk(node)", "        enter(node)",
                   "        listener_children(node).each { |child| walk(child) }", "        exit(node)", "        node",
                   "      end", "")
        append_listener_dispatch(lines, definitions, :enter)
        lines << ""
        append_listener_dispatch(lines, definitions, :exit)
        lines << ""
        definitions.each_value do |node|
          method = ast_method_name(node.fetch(:name))
          lines.push("      def enter_#{method}(_node); end", "      def exit_#{method}(_node); end")
        end
        lines << ""
        lines.push(
          "      def listener_children(node)",
          "        return node if node.is_a?(Array)",
          "        return node.deconstruct if node.respond_to?(:deconstruct)",
          "",
          "        []",
          "      end",
          "    end"
        )
      end

      # @rbs (Array[String] lines, Hash[String, IR::node_annotation] definitions, :enter | :exit kind) -> void
      def append_listener_dispatch(lines, definitions, kind)
        lines.push("      def #{kind}(node)", "        case node")
        definitions.each_value do |node|
          method = ast_method_name(node.fetch(:name))
          lines << "        when #{node.fetch(:name)} then #{kind}_#{method}(node)"
        end
        lines.push("        end", "      end")
      end

      # @rbs (IR::Production production) -> String
      def ast_node_action_source(production)
        node = production.node || raise(Ibex::Error, "missing AST node metadata")
        arguments = node.fetch(:fields).each_index.map do |index|
          "#{node.fetch(:fields).fetch(index)}: val[#{index}]"
        end
        [
          "private def _ibex_action_#{production.id}" \
          "(val, _values, _ibex_locations, _ibex_location_stack, _ibex_location)",
          "  AST::#{node.fetch(:name)}.new(#{arguments.join(', ')})",
          "end"
        ].join("\n")
      end

      # @rbs (String name) -> String
      def ast_method_name(name)
        name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
      end
    end
  end
end
