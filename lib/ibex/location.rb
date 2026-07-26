# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  # Immutable source range suitable for lexer tokens and parser diagnostics.
  #
  # Coordinates are one-based. Byte offsets are optional, zero-based, and
  # half-open. Keeping both forms lets Unicode-aware lexers report human
  # columns without losing an exact source slice.
  class Location
    attr_reader :file #: String?
    attr_reader :line #: Integer
    attr_reader :column #: Integer
    attr_reader :end_line #: Integer
    attr_reader :end_column #: Integer
    attr_reader :start_byte #: Integer?
    attr_reader :end_byte #: Integer?
    attr_reader :source_line #: String?

    # @rbs (?file: String?, line: Integer, column: Integer, ?end_line: Integer?,
    #   ?end_column: Integer?, ?start_byte: Integer?, ?end_byte: Integer?, ?source_line: String?) -> void
    def initialize(line:, column:, file: nil, end_line: nil, end_column: nil,
                   start_byte: nil, end_byte: nil, source_line: nil)
      @file = file&.dup&.freeze
      @line = positive_coordinate(:line, line)
      @column = positive_coordinate(:column, column)
      @end_line = positive_coordinate(:end_line, end_line || line)
      @end_column = positive_coordinate(:end_column, end_column || column)
      @start_byte = optional_offset(:start_byte, start_byte)
      @end_byte = optional_offset(:end_byte, end_byte)
      @source_line = source_line&.dup&.freeze
      validate_order!
      freeze
    end

    # Return the smallest range covering both locations.
    # @rbs (Location other) -> Location
    def join(other)
      raise ArgumentError, "location files differ" unless file == other.file

      first = before_or_equal?(self, other) ? self : other
      ending = before_or_equal_end?(self, other) ? other : self
      self.class.new(
        file: file, line: first.line, column: first.column,
        end_line: ending.end_line, end_column: ending.end_column,
        start_byte: joined_start_byte(other), end_byte: joined_end_byte(other),
        source_line: first.source_line
      )
    end

    # Fold a nonempty collection into one covering range.
    # @rbs (Enumerable[Location] locations) -> Location
    def self.join(locations)
      values = locations.to_a
      first = values.shift || raise(ArgumentError, "locations must not be empty")
      values.reduce(first) { |combined, location| combined.join(location) }
    end

    # @rbs () -> bool
    def empty?
      @line == @end_line && @column == @end_column &&
        (@start_byte.nil? || @end_byte.nil? || @start_byte == @end_byte)
    end

    # @rbs () -> Hash[Symbol, untyped]
    def to_h
      {
        file: @file, line: @line, column: @column,
        end_line: @end_line, end_column: @end_column,
        start_byte: @start_byte, end_byte: @end_byte
      }.compact
    end

    private

    # @rbs (Symbol name, untyped value) -> Integer
    def positive_coordinate(name, value)
      return value if value.is_a?(Integer) && value.positive?

      raise ArgumentError, "#{name} must be a positive Integer"
    end

    # @rbs (Symbol name, untyped value) -> Integer?
    def optional_offset(name, value)
      return if value.nil?
      return value if value.is_a?(Integer) && value >= 0

      raise ArgumentError, "#{name} must be a nonnegative Integer or nil"
    end

    # @rbs () -> void
    def validate_order!
      if @end_line < @line || (@end_line == @line && @end_column < @column)
        raise ArgumentError, "end position precedes start position"
      end

      start_byte = @start_byte
      end_byte = @end_byte
      return unless start_byte && end_byte && end_byte < start_byte

      raise ArgumentError, "end_byte precedes start_byte"
    end

    # @rbs (Location left, Location right) -> bool
    def before_or_equal?(left, right)
      left.line < right.line || (left.line == right.line && left.column <= right.column)
    end

    # @rbs (Location left, Location right) -> bool
    def before_or_equal_end?(left, right)
      left.end_line < right.end_line ||
        (left.end_line == right.end_line && left.end_column <= right.end_column)
    end

    # @rbs (Location other) -> Integer?
    def joined_start_byte(other)
      return unless @start_byte && other.start_byte

      [@start_byte, other.start_byte].min
    end

    # @rbs (Location other) -> Integer?
    def joined_end_byte(other)
      return unless @end_byte && other.end_byte

      [@end_byte, other.end_byte].max
    end
  end
end
