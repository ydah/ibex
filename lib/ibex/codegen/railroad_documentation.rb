# frozen_string_literal: true

module Ibex
  module Codegen
    # Documentation layout helpers mixed into the railroad renderer singleton.
    module RailroadDocumentation
      DOCUMENTATION_COLUMNS = 72 #: Integer
      DOCUMENTATION_LINE_HEIGHT = 18 #: Integer
      DOCUMENTATION_GAP = 8 #: Integer

      private

      # @rbs (Array[String] lines, IR::GrammarSymbol symbol) -> void
      def append_rule_documentation(lines, symbol)
        # @type self: singleton(Railroad)
        documentation = symbol.documentation
        return unless documentation

        lines << "    <desc>#{escape(documentation)}</desc>"
        documentation_lines(documentation).each_with_index do |line, index|
          y = Railroad::SECTION_HEADER + DOCUMENTATION_GAP + (index * DOCUMENTATION_LINE_HEIGHT)
          lines << %(    <text class="rule-documentation" x="#{Railroad::PAGE_PADDING}" y="#{y}">#{escape(line)}</text>)
        end
      end

      # @rbs (IR::GrammarSymbol symbol) -> Integer
      def section_header_height(symbol)
        # @type self: singleton(Railroad)
        lines = documentation_lines(symbol.documentation)
        return Railroad::SECTION_HEADER if lines.empty?

        Railroad::SECTION_HEADER + DOCUMENTATION_GAP + (lines.length * DOCUMENTATION_LINE_HEIGHT)
      end

      # @rbs (String? documentation) -> Array[String]
      def documentation_lines(documentation)
        return [] unless documentation

        documentation.split("\n", -1).flat_map do |line|
          characters = line.each_char.to_a
          characters.empty? ? [""] : characters.each_slice(DOCUMENTATION_COLUMNS).map(&:join)
        end
      end

      # @rbs (String | Integer value) -> String
      def escape(value)
        xml = value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
                   .gsub(/[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD\u{10000}-\u{10FFFF}]/u, "\uFFFD")
        xml.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
           .gsub('"', "&quot;").gsub("'", "&apos;")
      end

      # @rbs (Integer from, Integer to) -> String
      def track(from, to)
        %(<line class="track" x1="#{from}" y1="0" x2="#{to}" y2="0"/>)
      end
    end
  end
end
