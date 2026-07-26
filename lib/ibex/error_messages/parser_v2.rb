# frozen_string_literal: true

module Ibex
  module ErrorMessages
    # Sentence-keyed ibex-messages v2 parsing, mixed into Parser so both
    # versions share UTF-8, escape, and positioned-diagnostic helpers.
    module ParserV2
      # @rbs!
      #   private def ignorable?: (String) -> bool
      #   private def column: (String) -> Integer
      #   private def fail_at: (Integer, Integer, String) -> bot
      #   private def decode_line: (String, Integer, Integer) -> String

      private

      # @rbs () -> Document
      def parse_v2
        entries = [] #: Array[Entry]
        identifiers = {} #: Hash[String, Integer]
        keys = {} #: Hash[String, Integer]
        index = 1
        while index < @lines.length
          line = @lines.fetch(index)
          if ignorable?(line) && !line.lstrip.start_with?("##")
            index += 1
            next
          end

          entry, index = parse_v2_entry(index)
          record_v2_entry(entry, entries, identifiers, keys)
        end
        Document.new(version: 2, entries: entries)
      end

      # @rbs (Entry entry, Array[Entry] entries, Hash[String, Integer] identifiers,
      #   Hash[String, Integer] keys) -> void
      def record_v2_entry(entry, entries, identifiers, keys)
        error_id = entry.error_id || raise(Ibex::Error, "missing error id")
        reject_v2_duplicate(identifiers, error_id, entry.line, "error id")
        key = entry.sentence ? "#{entry.entry}\0#{entry.sentence.join("\0")}" : "legacy\0#{entry.state}"
        reject_v2_duplicate(keys, key, entry.line, "sentence")
        identifiers[error_id] = entry.line
        keys[key] = entry.line
        entries << entry
      end

      # @rbs (Integer opening_index) -> [Entry, Integer]
      def parse_v2_entry(opening_index)
        status, sentence, state = parse_v2_opening(opening_index)
        read_v2_entry_body(opening_index, status, sentence, state)
      end

      # @rbs (Integer opening_index) ->
      #   [:active | :unreachable | :removed, Array[String]?, Integer?]
      def parse_v2_opening(opening_index)
        opening = @lines.fetch(opening_index)
        if (legacy = opening.match(/\Alegacy-state:[ \t]*([0-9]+)\z/))
          return [:removed, nil, Integer(legacy[1] || "0", 10)]
        end

        if (sentence = opening.match(/\A(sentence|unreachable):[ \t]*(.*)\z/))
          status = sentence[1] == "unreachable" ? :unreachable : :active #: :unreachable | :active
          return [status, parse_sentence(sentence[2] || "", opening_index + 1), nil]
        end

        fail_at(opening_index + 1, column(opening),
                "expected `sentence: TOKENS`, `unreachable: TOKENS`, or `legacy-state: N`")
      end

      # @rbs (Integer opening_index, :active | :unreachable | :removed status, Array[String]? sentence,
      #   Integer? state) -> [Entry, Integer]
      def read_v2_entry_body(opening_index, status, sentence, state)
        error_id = nil #: String?
        entry_name = nil #: String?
        message_lines = [] #: Array[String]
        index = opening_index + 1
        while index < @lines.length
          line = @lines.fetch(index)
          if line.strip == "end"
            return close_v2_entry(
              opening_index, index, status, sentence, state, error_id, entry_name, message_lines
            )
          end

          error_id, state, entry_name = read_v2_metadata(
            line, index, error_id, state, entry_name, message_lines
          )
          index += 1
        end
        fail_at(opening_index + 1, 1, "unterminated error-sentence entry")
      end

      # @rbs (Integer opening_index, Integer index, :active | :unreachable | :removed status,
      #   Array[String]? sentence, Integer? state, String? error_id, String? entry_name,
      #   Array[String] message_lines) -> [Entry, Integer]
      def close_v2_entry(opening_index, index, status, sentence, state, error_id, entry_name, message_lines)
        fail_at(opening_index + 1, 1, "missing `## E0001` error id") unless error_id
        message = message_lines.empty? ? nil : message_lines.join("\n")
        fail_at(opening_index + 1, 1, "message must not be empty") if message&.strip&.empty?
        entry = Entry.new(
          state: state, status: status, message: message, line: opening_index + 1,
          sentence: sentence, error_id: error_id, entry: entry_name
        )
        [entry, index + 1]
      end

      # @rbs (String line, Integer index, String? error_id, Integer? state, String? entry_name,
      #   Array[String] message_lines) -> [String?, Integer?, String?]
      def read_v2_metadata(line, index, error_id, state, entry_name, message_lines)
        stripped = line.strip
        if (match = stripped.match(/\A##[ \t]+(E[0-9]{4,})\z/))
          fail_at(index + 1, column(line), "duplicate error id") if error_id
          error_id = match[1]
        elsif (match = stripped.match(/\A# state:[ \t]*([0-9]+)\z/))
          state = Integer(match[1] || "0", 10)
        elsif (match = stripped.match(/\A# entry:[ \t]*(\S+)\z/))
          entry_name = match[1]
        elsif line.start_with?("|")
          append_v2_message_line(message_lines, line, index)
        elsif !ignorable?(line)
          fail_at(index + 1, column(line), "expected metadata, a `| ` message line, a comment, or `end`")
        end
        [error_id, state, entry_name]
      end

      # @rbs (Array[String] message_lines, String line, Integer index) -> void
      def append_v2_message_line(message_lines, line, index)
        content = line.delete_prefix("|").delete_prefix(" ")
        content_column = line.start_with?("| ") ? 3 : 2
        message_lines << decode_line(content, index + 1, content_column)
      end

      # @rbs (String source, Integer line) -> Array[String]
      def parse_sentence(source, line)
        tokens = [] #: Array[String]
        index = 0
        loop do
          index = skip_sentence_space(source, index)
          break if index == source.length

          token, index = read_sentence_token(source, index, line)
          tokens << token
        end
        fail_at(line, 1, "error sentence must contain at least one token") if tokens.empty?
        tokens
      end

      # @rbs (String source, Integer index) -> Integer
      def skip_sentence_space(source, index)
        index += 1 while index < source.length && source[index]&.match?(/\s/)
        index
      end

      # @rbs (String source, Integer index, Integer line) -> [String, Integer]
      def read_sentence_token(source, index, line)
        start = index
        quote = source[index]
        if ["'", '"'].include?(quote)
          index = quoted_token_end(source, index, quote || "", line)
        else
          index += 1 while index < source.length && !source[index]&.match?(/\s/)
        end
        token = source[start...index] || raise(Ibex::Error, "missing sentence token")
        [token, index]
      end

      # @rbs (String source, Integer index, String quote, Integer line) -> Integer
      def quoted_token_end(source, index, quote, line)
        ending = scan_quoted_token(source, index, quote, line)
        return ending if ending == source.length || source[ending]&.match?(/\s/)

        fail_at(line, ending + 1, "quoted token must be followed by whitespace")
      end

      # @rbs (String source, Integer index, String quote, Integer line) -> Integer
      def scan_quoted_token(source, index, quote, line)
        index += 1
        while index < source.length
          character = source[index]
          if character == "\\"
            index += 2
          elsif character == quote
            return index + 1
          else
            index += 1
          end
        end
        fail_at(line, source.length + 1, "unterminated quoted token")
      end

      # @rbs (Hash[String, Integer] declarations, String key, Integer line, String label) -> void
      def reject_v2_duplicate(declarations, key, line, label)
        previous = declarations[key]
        fail_at(line, 1, "duplicate #{label}; first declared at line #{previous}") if previous
      end
    end
  end
end
