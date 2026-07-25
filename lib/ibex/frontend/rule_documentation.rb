# frozen_string_literal: true

module Ibex
  module Frontend
    # Attaches immediately preceding lossless line-comment blocks to parsed rules.
    class RuleDocumentation
      EMPTY_SEGMENTS = Array.new(0).freeze #: Array[Segment]
      private_constant :EMPTY_SEGMENTS

      # @rbs (AST::Root | AST::Fragment node, SourceDocument document) -> (AST::Root | AST::Fragment)
      def self.enrich(node, document)
        new(document).enrich(node)
      end

      # @rbs (SourceDocument document) -> void
      def initialize(document)
        @segments_by_line = index_segments(document) #: Hash[Integer, Array[Segment]]
      end

      # @rbs (AST::Root | AST::Fragment node) -> (AST::Root | AST::Fragment)
      def enrich(node)
        rules = node.rules.map { |rule| documented_rule(rule) }
        if node.is_a?(AST::Root)
          AST::Root.new(
            class_name: node.class_name, superclass: node.superclass, declarations: node.declarations,
            rules: rules, user_code: node.user_code, loc: node.loc
          )
        else
          AST::Fragment.new(declarations: node.declarations, rules: rules, loc: node.loc)
        end
      end

      private

      # @rbs (AST::Rule rule) -> AST::Rule
      def documented_rule(rule)
        AST::Rule.new(
          lhs: rule.lhs, alternatives: rule.alternatives, loc: rule.loc,
          documentation: documentation_before(rule.loc.line)
        )
      end

      # @rbs (Integer rule_line) -> String?
      def documentation_before(rule_line)
        lines = [] #: Array[String]
        line = rule_line - 1
        while line.positive?
          content = documentation_line(line)
          break unless content

          lines.unshift(content)
          line -= 1
        end
        lines.empty? ? nil : lines.join("\n").freeze
      end

      # @rbs (Integer line) -> String?
      def documentation_line(line)
        segments = @segments_by_line.fetch(line, EMPTY_SEGMENTS)
        comments = segments.select { |segment| segment.kind == :line_comment }
        return unless comments.length == 1

        comment = comments.fetch(0)
        return unless comment.text.start_with?("##")
        return unless segments.all? { |segment| documentation_line_segment?(segment, comment) }

        comment.text.delete_prefix("##").delete_prefix(" ")
      end

      # @rbs (Segment segment, Segment comment) -> bool
      def documentation_line_segment?(segment, comment)
        segment.equal?(comment) || %i[whitespace newline].include?(segment.kind)
      end

      # @rbs (SourceDocument document) -> Hash[Integer, Array[Segment]]
      def index_segments(document)
        indexed = Hash.new { |hash, line| hash[line] = [] } #: Hash[Integer, Array[Segment]]
        document.cst.each do |segment|
          covered_lines(segment).each { |line| indexed[line] << segment }
        end
        indexed
      end

      # @rbs (Segment segment) -> Array[Integer]
      def covered_lines(segment)
        first = segment.span.start.line
        return [first] if segment.kind == :newline

        (first..segment.span.finish.line).to_a
      end
    end
  end
end
