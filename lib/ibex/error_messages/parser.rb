# frozen_string_literal: true

module Ibex
  module ErrorMessages
    # Strict line-oriented parser for the ibex-messages v1 format.
    class Parser
      ESCAPES = { "\\" => "\\", "n" => "\n", "t" => "\t", "r" => "\r" }.freeze

      # @rbs @file: String
      # @rbs @lines: Array[String]

      # @rbs (String source, file: String) -> void
      def initialize(source, file:)
        @file = file
        text = source.dup.force_encoding(Encoding::UTF_8)
        fail_at(1, 1, "messages file must be valid UTF-8") unless text.valid_encoding?

        @lines = text.lines(chomp: true)
      end

      # @rbs () -> Document
      def parse
        validate_header
        entries = [] #: Array[Entry]
        declarations = {} #: Hash[Integer, Integer]
        index = 1
        while index < @lines.length
          line = @lines.fetch(index)
          if ignorable?(line)
            index += 1
            next
          end

          match = line.strip.match(/\A(state|removed)\s+([0-9]+)\z/)
          fail_at(index + 1, column(line), top_level_expectation) unless match
          state_text = match[2] || raise(Ibex::Error, "missing state number")
          state = Integer(state_text, 10)
          reject_duplicate(declarations, state, index, line)
          declarations[state] = index + 1
          entry, index = parse_entry(index, state, match[1] == "state" ? :active : :removed)
          entries << entry
        end
        Document.new(entries: entries)
      end

      private

      # @rbs () -> void
      def validate_header
        header = @lines.first&.delete_prefix("\uFEFF")
        fail_at(1, 1, "expected #{HEADER.inspect}") unless header == HEADER
      end

      # @rbs (Hash[Integer, Integer] declarations, Integer state, Integer index, String line) -> void
      def reject_duplicate(declarations, state, index, line)
        return unless declarations.key?(state)

        fail_at(index + 1, column(line),
                "duplicate state #{state}; first declared at line #{declarations.fetch(state)}")
      end

      # @rbs (Integer opening_index, Integer state, :active | :removed status) -> [Entry, Integer]
      def parse_entry(opening_index, state, status)
        message_lines = [] #: Array[String]
        index = opening_index + 1
        while index < @lines.length
          line = @lines.fetch(index)
          return close_entry(message_lines, opening_index, index, state, status) if line.strip == "end"

          read_entry_line(message_lines, line, index)
          index += 1
        end
        label = status == :active ? "state" : "removed"
        fail_at(opening_index + 1, 1, "unterminated #{label} #{state} entry")
      end

      # @rbs (Array[String] message_lines, Integer opening_index, Integer index, Integer state,
      #   :active | :removed status) -> [Entry, Integer]
      def close_entry(message_lines, opening_index, index, state, status)
        message = message_lines.empty? ? nil : message_lines.join("\n")
        fail_at(opening_index + 1, 1, "message for state #{state} must not be empty") if message&.strip&.empty?

        entry = Entry.new(state: state, status: status, message: message, line: opening_index + 1)
        [entry, index + 1]
      end

      # @rbs (Array[String] message_lines, String line, Integer index) -> void
      def read_entry_line(message_lines, line, index)
        return if ignorable?(line)

        unless line.start_with?("|")
          fail_at(index + 1, column(line), "expected a `| ` message line, a comment, a blank line, or `end`")
        end

        content = line.delete_prefix("|")
        content = content.delete_prefix(" ")
        content_column = line.start_with?("| ") ? 3 : 2
        message_lines << decode_line(content, index + 1, content_column)
      end

      # @rbs (String content, Integer line, Integer content_column) -> String
      def decode_line(content, line, content_column)
        decoded = +""
        index = 0
        while index < content.length
          character = content[index] || raise(Ibex::Error, "missing message character")
          unless character == "\\"
            decoded << character
            index += 1
            next
          end

          escaped = content[index + 1]
          fail_at(line, content_column + index, "trailing backslash in message line") unless escaped
          replacement = ESCAPES[escaped]
          fail_at(line, content_column + index, "unknown escape \\#{escaped}") unless replacement

          decoded << replacement
          index += 2
        end
        decoded
      end

      # @rbs (String line) -> bool
      def ignorable?(line)
        line.strip.empty? || line.lstrip.start_with?("#")
      end

      # @rbs () -> String
      def top_level_expectation
        "expected `state N`, `removed N`, a comment, or a blank line"
      end

      # @rbs (String line) -> Integer
      def column(line)
        (line.index(/\S/) || 0) + 1
      end

      # @rbs (Integer line, Integer column, String message) -> bot
      def fail_at(line, column, message)
        raise Ibex::Error, "#{@file}:#{line}:#{column}: #{message}"
      end
    end
  end
end
