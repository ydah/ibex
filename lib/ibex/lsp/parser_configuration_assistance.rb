# frozen_string_literal: true

module Ibex
  module LSP
    # Provides static editor assistance for the root parser declaration without evaluating grammar code.
    class ParserConfigurationAssistance
      SETTING_VALUES = Frontend::ParserConfigurationSupport::PARSER_SETTING_VALUES #: Hash[String, Array[String]]
      SETTING_DOCUMENTATION = {
        "algorithm" => "`parser.algorithm` selects parser-table construction. Values: `slr`, `lalr`, `ielr`, `lr1`.",
        "entries" => "`parser.entries` selects shared or isolated construction for multiple start symbols. " \
                     "Values: `shared`, `isolated`.",
        "cst_trivia" => "`cst.trivia` selects CST trivia ownership. Values: `leading`, `balanced`, `drop`; " \
                        "requires `pragma cst`."
      }.freeze #: Hash[String, String]
      VALUE_DOCUMENTATION = {
        "slr" => "`slr` — SLR parser-table construction.",
        "lalr" => "`lalr` — LALR parser-table construction.",
        "ielr" => "`ielr` — IELR parser-table construction with canonical LR(1) verification support.",
        "lr1" => "`lr1` — canonical LR(1) parser-table construction.",
        "shared" => "`shared` — construct multiple entries in one shared automaton.",
        "isolated" => "`isolated` — construct each of multiple entries independently.",
        "leading" => "`leading` — attach leading trivia to the following CST node.",
        "balanced" => "`balanced` — attach trivia between the surrounding CST nodes.",
        "drop" => "`drop` — omit CST trivia; location and incremental APIs are unavailable."
      }.freeze #: Hash[String, String]

      # @rbs (DocumentStore store, String path) -> void
      def initialize(store, path)
        @store = store
        @path = path
      end

      # @rbs (lsp_object position) -> lsp_object
      def completion(position)
        source = source!
        codec = PositionCodec.new(source)
        offset = codec.byte_offset(position)
        line_start = line_start(source, offset)
        return completion_list([]) unless parser_block_open?(source.byteslice(0, line_start) || "")

        prefix = source.byteslice(line_start, offset - line_start) || ""
        value_match = prefix.match(/\A\s*(algorithm|entries|cst_trivia)\s+([A-Za-z_]*)\z/)
        if value_match
          setting = value_match[1] || raise("parser setting capture is missing")
          return completion_list(value_items(setting))
        end
        return completion_list(setting_items) if prefix.match?(/\A\s*[A-Za-z_]*\z/)

        completion_list([])
      end

      # @rbs (lsp_object position) -> lsp_object?
      def hover(position)
        source = source!
        codec = PositionCodec.new(source)
        offset = codec.byte_offset(position)
        start = line_start(source, offset)
        return unless parser_block_open?(source.byteslice(0, start) || "")

        finish = source.index("\n", start) || source.bytesize
        line = source.byteslice(start, finish - start) || ""
        match = line.match(
          /\A\s*(algorithm|entries|cst_trivia)\s+(slr|lalr|ielr|lr1|shared|isolated|leading|balanced|drop)\s*(?:#.*)?\z/
        )
        return unless match

        token, token_start, token_end = hovered_token(match, line, start, offset)
        return unless token

        documentation = SETTING_DOCUMENTATION[token] || VALUE_DOCUMENTATION[token]
        {
          "contents" => { "kind" => "markdown", "value" => documentation },
          "range" => { "start" => codec.position(token_start), "end" => codec.position(token_end) }
        }
      end

      private

      # @rbs () -> String
      def source!
        snapshot = @store.snapshot_for(@path)
        raise ArgumentError, "document is unavailable" unless snapshot

        snapshot.fetch(:source)
      end

      # @rbs (String source, Integer offset) -> Integer
      def line_start(source, offset)
        newline = offset.positive? ? source.rindex("\n", offset - 1) : nil
        newline ? newline + 1 : 0
      end

      # @rbs (String source) -> bool
      def parser_block_open?(source)
        root = false
        open = false
        source.each_line do |line|
          content = line.sub(/#.*/, "").strip
          next if content.empty?

          root = true if content.match?(/\Aclass\b/)
          root = false if content.match?(/\Afragment\b/)
          open = true if root && content == "parser"
          open = false if open && content == "end"
          return false if content.match?(/\Arule\b/)
        end
        root && open
      end

      # @rbs () -> Array[lsp_object]
      def setting_items
        SETTING_VALUES.keys.map do |name|
          completion_item(name, 10, SETTING_DOCUMENTATION.fetch(name))
        end
      end

      # @rbs (String setting) -> Array[lsp_object]
      def value_items(setting)
        SETTING_VALUES.fetch(setting).map do |name|
          completion_item(name, 12, VALUE_DOCUMENTATION.fetch(name))
        end
      end

      # @rbs (String label, Integer kind, String documentation) -> lsp_object
      def completion_item(label, kind, documentation)
        { "label" => label, "kind" => kind, "documentation" => { "kind" => "markdown", "value" => documentation } }
      end

      # @rbs (Array[lsp_object] items) -> lsp_object
      def completion_list(items)
        { "isIncomplete" => false, "items" => items }
      end

      # @rbs (MatchData match, String line, Integer line_start, Integer offset) -> [String?, Integer, Integer]
      def hovered_token(match, line, line_start, offset)
        [1, 2].each do |capture|
          token = match[capture]
          next unless token

          before = line[0...match.begin(capture)] || ""
          start = line_start + before.bytesize
          finish = start + token.bytesize
          return [token, start, finish] if offset.between?(start, finish - 1)
        end
        [nil, offset, offset]
      end
    end
  end
end
