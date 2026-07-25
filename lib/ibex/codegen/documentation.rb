# frozen_string_literal: true

require_relative "railroad"
require_relative "symbol_labels"

module Ibex
  module Codegen
    # Renders normalized user rules as deterministic Markdown, HTML, or railroad SVG.
    module Documentation
      FORMATS = %w[markdown html railroad].freeze #: Array[String]

      class << self
        # @rbs (IR::Grammar grammar, format: String | Symbol) -> String
        def render(grammar, format:)
          case format.to_s
          when "markdown" then render_markdown(grammar)
          when "html" then render_html(grammar)
          when "railroad" then Railroad.render(grammar)
          else raise ArgumentError, "unsupported documentation format #{format.inspect}"
          end
        end

        private

        # @rbs (IR::Grammar grammar) -> String
        def render_markdown(grammar)
          labels = SymbolLabels.build(grammar)
          lines = ["# #{markdown_escape(grammar.class_name)} grammar", ""]
          rule_groups(grammar).each do |symbol, productions|
            lines << "## #{markdown_code(labels.fetch(symbol.id))}"
            lines << ""
            append_markdown_documentation(lines, symbol.documentation)
            lines << "Alternatives:"
            lines << ""
            productions.each do |production|
              lines << "- #{markdown_alternative(grammar, production, labels)}"
            end
            lines << ""
          end
          "#{lines.join("\n").rstrip}\n"
        end

        # @rbs (Array[String] lines, String? documentation) -> void
        def append_markdown_documentation(lines, documentation)
          return unless documentation

          documentation.split("\n", -1).each do |line|
            escaped = markdown_escape(line)
            lines << (escaped.empty? ? ">" : "> #{escaped}")
          end
          lines << ""
        end

        # @rbs (IR::Grammar grammar, IR::Production production, Hash[Integer, String] labels) -> String
        def markdown_alternative(grammar, production, labels)
          return "ε" if production.rhs.empty?

          production.rhs.map do |symbol_id|
            raise Ibex::Error, "missing grammar symbol id #{symbol_id}" unless grammar.symbol_by_id(symbol_id)

            markdown_code(labels.fetch(symbol_id))
          end.join(" ")
        end

        # @rbs (IR::Grammar grammar) -> String
        def render_html(grammar)
          labels = SymbolLabels.build(grammar)
          title = "#{html_escape(grammar.class_name)} grammar"
          lines = html_start(title)
          rule_groups(grammar).each do |symbol, productions|
            append_html_rule(lines, grammar, symbol, productions, labels)
          end
          lines.push("  </main>", "</body>", "</html>")
          "#{lines.join("\n")}\n"
        end

        # @rbs (String title) -> Array[String]
        def html_start(title)
          [
            "<!doctype html>",
            "<html lang=\"en\">",
            "<head>",
            "  <meta charset=\"utf-8\">",
            "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
            "  <title>#{title}</title>",
            "  <style>",
            "    body { color: #172033; background: #fff; font: 16px/1.6 system-ui, sans-serif; margin: 0; }",
            "    main { max-width: 72rem; margin: 0 auto; padding: 2rem; }",
            "    section { border-top: 1px solid #d8dee9; padding: 1.25rem 0; }",
            "    code { background: #f3f6fa; border-radius: .25rem; padding: .1rem .3rem; }",
            "    .documentation { white-space: normal; }",
            "    .alternatives { padding-left: 1.5rem; }",
            "  </style>",
            "</head>",
            "<body>",
            "  <main>",
            "    <h1>#{title}</h1>"
          ]
        end

        # @rbs (Array[String] lines, IR::Grammar grammar, IR::GrammarSymbol symbol,
        #   Array[IR::Production] productions, Hash[Integer, String] labels) -> void
        def append_html_rule(lines, grammar, symbol, productions, labels)
          label = html_escape(labels.fetch(symbol.id))
          lines << "    <section aria-labelledby=\"rule-#{symbol.id}\">"
          lines << "      <h2 id=\"rule-#{symbol.id}\"><code>#{label}</code></h2>"
          if symbol.documentation
            documentation = symbol.documentation.split("\n", -1).map { |line| html_escape(line) }.join("<br>\n        ")
            lines << "      <p class=\"documentation\">#{documentation}</p>"
          end
          lines << "      <ol class=\"alternatives\" aria-label=\"Alternatives for #{label}\">"
          productions.each do |production|
            lines << "        <li>#{html_alternative(grammar, production, labels)}</li>"
          end
          lines << "      </ol>"
          lines << "    </section>"
        end

        # @rbs (IR::Grammar grammar, IR::Production production, Hash[Integer, String] labels) -> String
        def html_alternative(grammar, production, labels)
          return "<span aria-label=\"empty\">ε</span>" if production.rhs.empty?

          production.rhs.map do |symbol_id|
            raise Ibex::Error, "missing grammar symbol id #{symbol_id}" unless grammar.symbol_by_id(symbol_id)

            "<code>#{html_escape(labels.fetch(symbol_id))}</code>"
          end.join(" ")
        end

        # @rbs (IR::Grammar grammar) -> Array[[IR::GrammarSymbol, Array[IR::Production]]]
        def rule_groups(grammar)
          grouped = grammar.productions.select { |production| production.origin[:kind].to_s == "user" }.group_by(&:lhs)
          grammar.nonterminals.filter_map do |symbol|
            productions = grouped[symbol.id]
            [symbol, productions] if productions
          end
        end

        # @rbs (String value) -> String
        def markdown_code(value)
          safe = html_escape(value)
          longest_run = safe.scan(/`+/).map(&:length).max.to_i
          delimiter = "`" * (longest_run + 1)
          padding = markdown_code_padding?(safe) ? " " : ""
          "#{delimiter}#{padding}#{safe}#{padding}#{delimiter}"
        end

        # @rbs (String value) -> bool
        def markdown_code_padding?(value)
          return true if value.start_with?("`") || value.end_with?("`")

          value.start_with?(" ") && value.end_with?(" ") && !value.match?(/\A +\z/)
        end

        # @rbs (String value) -> String
        def markdown_escape(value)
          html_escape(value).gsub(/([\\`*_{}\[\]()#+\-.!|>])/) { |match| "\\#{match}" }
        end

        # @rbs (String value) -> String
        def html_escape(value)
          safe = value.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
                      .gsub(/[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD\u{10000}-\u{10FFFF}]/u, "\uFFFD")
          safe.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
              .gsub('"', "&quot;").gsub("'", "&#39;")
        end
      end
    end
  end
end
