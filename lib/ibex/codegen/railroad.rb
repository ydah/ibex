# frozen_string_literal: true

require_relative "symbol_labels"

module Ibex
  module Codegen
    # Renders normalized Grammar IR as a self-contained SVG railroad diagram.
    module Railroad
      CHAR_WIDTH = 8 #: Integer
      BOX_HEIGHT = 28 #: Integer
      BOX_PADDING = 20 #: Integer
      TRACK_GAP = 18 #: Integer
      ROW_HEIGHT = 46 #: Integer
      SECTION_HEADER = 30 #: Integer
      SECTION_GAP = 18 #: Integer
      PAGE_PADDING = 20 #: Integer
      TITLE_HEIGHT = 48 #: Integer
      EPSILON_WIDTH = 34 #: Integer
      START_RADIUS = 4 #: Integer
      END_RADIUS = 6 #: Integer
      MIN_RAIL_X = 180 #: Integer
      # @rbs STYLE: String
      STYLE = <<~CSS
        text { fill: #172033; font: 14px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
        .diagram-title { font-size: 18px; font-weight: 700; }
        .rule-name { font-weight: 700; }
        .production-id { fill: #697386; font-size: 11px; text-anchor: end; }
        .track { fill: none; stroke: #697386; stroke-width: 2; }
        .start { fill: #172033; }
        .end { fill: #fff; stroke: #172033; stroke-width: 2; }
        .end-dot { fill: #172033; }
        .symbol { stroke: #172033; stroke-width: 1.5; }
        .terminal { fill: #fff3df; }
        .nonterminal { fill: #e8f1ff; }
        .symbol-label { text-anchor: middle; }
        .epsilon { fill: #697386; font-style: italic; text-anchor: middle; }
      CSS

      class << self
        # @rbs (IR::Grammar grammar) -> String
        def render(grammar)
          labels = SymbolLabels.build(grammar)
          groups = production_groups(grammar)
          rail_x = [MIN_RAIL_X, groups.map { |symbol, _| label_width(labels.fetch(symbol.id)) }.max.to_i + 44].max
          width = document_width(grammar, groups, labels, rail_x)
          height = document_height(groups)
          lines = document_start(grammar, width, height)
          append_sections(lines, grammar, groups, labels, rail_x)
          lines << "</svg>"
          "#{lines.join("\n")}\n"
        end

        private

        # @rbs (IR::Grammar grammar) -> Array[[IR::GrammarSymbol, Array[IR::Production]]]
        def production_groups(grammar)
          grouped = grammar.productions.group_by(&:lhs)
          grammar.nonterminals.map { |symbol| [symbol, grouped.fetch(symbol.id, [])] }
        end

        # @rbs (IR::Grammar grammar, Array[[IR::GrammarSymbol, Array[IR::Production]]] groups,
        #   Hash[Integer, String] labels, Integer rail_x) -> Integer
        def document_width(grammar, groups, labels, rail_x)
          rows = groups.flat_map(&:last)
          widest = rows.map { |production| row_end_x(grammar, production, labels, rail_x) }.max
          [widest.to_i + PAGE_PADDING, label_width("#{grammar.class_name} grammar") + (PAGE_PADDING * 2), 360].max
        end

        # @rbs (Array[[IR::GrammarSymbol, Array[IR::Production]]] groups) -> Integer
        def document_height(groups)
          sections = groups.sum { |_symbol, productions| SECTION_HEADER + ([productions.length, 1].max * ROW_HEIGHT) }
          TITLE_HEIGHT + sections + (SECTION_GAP * [groups.length - 1, 0].max) + PAGE_PADDING
        end

        # @rbs (IR::Grammar grammar, Integer width, Integer height) -> Array[String]
        def document_start(grammar, width, height)
          title = escape(grammar.class_name)
          [
            %(<?xml version="1.0" encoding="UTF-8"?>),
            %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{width} #{height}" width="#{width}" ),
            %(     height="#{height}" role="img" aria-labelledby="railroad-title">),
            "  <title id=\"railroad-title\">Railroad diagram for #{title}</title>",
            "  <style>",
            STYLE.lines.map { |line| "    #{line.rstrip}" }.join("\n"),
            "  </style>",
            "  <text class=\"diagram-title\" x=\"#{PAGE_PADDING}\" y=\"30\">#{title} grammar</text>"
          ]
        end

        # @rbs (Array[String] lines, IR::Grammar grammar,
        #   Array[[IR::GrammarSymbol, Array[IR::Production]]] groups,
        #   Hash[Integer, String] labels, Integer rail_x) -> void
        def append_sections(lines, grammar, groups, labels, rail_x)
          y = TITLE_HEIGHT
          groups.each do |symbol, productions|
            lines << %(  <g id="nonterminal-#{escape(symbol.id)}" class="rule" transform="translate(0 #{y})">)
            lines << %(    <text class="rule-name" x="#{PAGE_PADDING}" y="20">#{escape(labels.fetch(symbol.id))}</text>)
            append_productions(lines, grammar, productions, labels, rail_x)
            lines << "  </g>"
            y += SECTION_HEADER + ([productions.length, 1].max * ROW_HEIGHT) + SECTION_GAP
          end
        end

        # @rbs (Array[String] lines, IR::Grammar grammar, Array[IR::Production] productions,
        #   Hash[Integer, String] labels, Integer rail_x) -> void
        def append_productions(lines, grammar, productions, labels, rail_x)
          if productions.empty?
            lines << %(    <text class="epsilon" x="#{rail_x}" y="#{SECTION_HEADER + 18}">∅</text>)
            return
          end
          productions.each_with_index do |production, index|
            y = SECTION_HEADER + (index * ROW_HEIGHT) + (BOX_HEIGHT / 2)
            lines.concat(production_lines(grammar, production, labels, rail_x, y))
          end
        end

        # @rbs (IR::Grammar grammar, IR::Production production, Hash[Integer, String] labels,
        #   Integer rail_x, Integer offset_y) -> Array[String]
        def production_lines(grammar, production, labels, rail_x, offset_y)
          lines = [
            %(<g class="production" data-production="#{escape(production.id)}" transform="translate(0 #{offset_y})">)
          ]
          lines << %(<text class="production-id" x="#{rail_x - 14}" y="4">p#{escape(production.id)}</text>)
          lines << %(<circle class="start" cx="#{rail_x}" cy="0" r="#{START_RADIUS}"/>)
          cursor = rail_x + START_RADIUS
          lines << track(cursor, cursor + TRACK_GAP)
          cursor += TRACK_GAP
          cursor = append_rhs(lines, grammar, production, labels, cursor)
          end_x = cursor + TRACK_GAP + END_RADIUS
          lines << track(cursor, end_x - END_RADIUS)
          lines << %(<circle class="end" cx="#{end_x}" cy="0" r="#{END_RADIUS}"/>)
          lines << %(<circle class="end-dot" cx="#{end_x}" cy="0" r="2"/>)
          lines << "</g>"
          lines.map { |line| "    #{line}" }
        end

        # @rbs (Array[String] lines, IR::Grammar grammar, IR::Production production,
        #   Hash[Integer, String] labels, Integer cursor) -> Integer
        def append_rhs(lines, grammar, production, labels, cursor)
          return append_epsilon(lines, cursor) if production.rhs.empty?

          production.rhs.each_with_index do |symbol_id, index|
            symbol = grammar.symbol_by_id(symbol_id) || raise(Ibex::Error, "missing grammar symbol id #{symbol_id}")
            width = label_width(labels.fetch(symbol_id))
            kind = symbol.terminal? ? "terminal" : "nonterminal"
            lines << "<rect class=\"symbol #{kind}\" x=\"#{cursor}\" y=\"#{-(BOX_HEIGHT / 2)}\" " \
                     "width=\"#{width}\" height=\"#{BOX_HEIGHT}\" rx=\"5\"/>"
            lines << "<text class=\"symbol-label\" x=\"#{cursor + (width / 2)}\" y=\"5\">" \
                     "#{escape(labels.fetch(symbol_id))}</text>"
            cursor += width
            next if index == production.rhs.length - 1

            lines << track(cursor, cursor + TRACK_GAP)
            cursor += TRACK_GAP
          end
          cursor
        end

        # @rbs (Array[String] lines, Integer cursor) -> Integer
        def append_epsilon(lines, cursor)
          lines << track(cursor, cursor + EPSILON_WIDTH)
          lines << %(<text class="epsilon" x="#{cursor + (EPSILON_WIDTH / 2)}" y="-6">ε</text>)
          cursor + EPSILON_WIDTH
        end

        # @rbs (IR::Grammar grammar, IR::Production production, Hash[Integer, String] labels,
        #   Integer rail_x) -> Integer
        def row_end_x(grammar, production, labels, rail_x)
          widths = production.rhs.map do |symbol_id|
            raise Ibex::Error, "missing grammar symbol id #{symbol_id}" unless grammar.symbol_by_id(symbol_id)

            label_width(labels.fetch(symbol_id))
          end
          content = widths.empty? ? EPSILON_WIDTH : widths.sum + (TRACK_GAP * [widths.length - 1, 0].max)
          rail_x + START_RADIUS + TRACK_GAP + content + TRACK_GAP + (END_RADIUS * 2)
        end

        # @rbs (String value) -> Integer
        def label_width(value)
          glyph_width = value.each_char.sum { |character| character.ascii_only? ? CHAR_WIDTH : CHAR_WIDTH * 2 }
          [glyph_width + BOX_PADDING, 38].max
        end

        # @rbs (Integer from, Integer to) -> String
        def track(from, to)
          %(<line class="track" x1="#{from}" y1="0" x2="#{to}" y2="0"/>)
        end

        # @rbs (String | Integer value) -> String
        def escape(value)
          xml = value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
                     .gsub(/[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD\u{10000}-\u{10FFFF}]/u, "\uFFFD")
          xml.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
             .gsub('"', "&quot;").gsub("'", "&apos;")
        end
      end
    end
  end
end
