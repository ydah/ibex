# frozen_string_literal: true

module Ibex
  module Frontend
    # Normalizes grammar source without changing its bytes.
    module SourceEncoding
      # @rbs (String source, String file) -> String
      def self.validated_utf8(source, file)
        validated = source.dup.force_encoding(Encoding::UTF_8)
        raise Ibex::Error, "#{file}: input must be valid UTF-8" unless validated.valid_encoding?

        validated.freeze
      end
    end

    # An immutable position in grammar source.
    class SourcePosition
      attr_reader :byte_offset #: Integer
      attr_reader :line #: Integer
      attr_reader :column #: Integer

      # @rbs (byte_offset: Integer, line: Integer, column: Integer) -> void
      def initialize(byte_offset:, line:, column:)
        raise ArgumentError, "byte_offset must be non-negative" if byte_offset.negative?
        raise ArgumentError, "line and column must be positive" unless line.positive? && column.positive?

        @byte_offset = byte_offset
        @line = line
        @column = column
        freeze
      end

      # @rbs () -> Hash[Symbol, Integer]
      def to_h
        { byte_offset: byte_offset, line: line, column: column }
      end
    end

    # An immutable half-open byte span in one grammar source.
    class SourceSpan
      attr_reader :file #: String
      attr_reader :start #: SourcePosition
      attr_reader :finish #: SourcePosition

      # @rbs (file: String, start: SourcePosition, finish: SourcePosition) -> void
      def initialize(file:, start:, finish:)
        raise ArgumentError, "span end precedes its start" if finish.byte_offset < start.byte_offset

        @file = file.dup.freeze
        @start = start
        @finish = finish
        freeze
      end

      # @rbs () -> Integer
      def start_byte
        start.byte_offset
      end

      # @rbs () -> Integer
      def end_byte
        finish.byte_offset
      end

      # @rbs () -> Integer
      def length
        end_byte - start_byte
      end

      # @rbs () -> bool
      def empty?
        length.zero?
      end

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        { file: file, start: start.to_h, end: finish.to_h }
      end
    end
  end
end
