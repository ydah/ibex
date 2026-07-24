# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # The deterministic source span assigned to a reduced nonterminal.
    #
    # Terminal stack entries retain the application-owned location object
    # supplied by the lexer. A reduction wraps the outer boundaries in this
    # immutable value so actions can distinguish synthesized spans.
    class LocationSpan
      attr_reader :start #: untyped
      attr_reader :finish #: untyped

      # @rbs (start: untyped, finish: untyped, ?empty: bool) -> void
      def initialize(start:, finish:, empty: false)
        @start = start
        @finish = finish
        @empty = empty
        freeze
      end

      # Build a span for an LR reduction. Nonempty reductions cover the first
      # through last located RHS entry. Empty reductions are zero-width at the
      # current lookahead location.
      # @rbs (Array[untyped] locations, lookahead: untyped) -> LocationSpan?
      def self.for_reduction(locations, lookahead:)
        if locations.empty?
          return unless lookahead

          boundary = boundary_start(lookahead)
          return new(start: boundary, finish: boundary, empty: true)
        end

        located = locations.compact
        return if located.empty?

        new(start: boundary_start(located.first), finish: boundary_finish(located.last))
      end

      # Whether this is the zero-width span of an empty production.
      # @rbs () -> bool
      def empty?
        @empty
      end

      # @rbs () -> untyped
      def file = location_value(@start, :file)

      # @rbs () -> untyped
      def line = location_value(@start, :line)

      # @rbs () -> untyped
      def column = location_value(@start, :column)

      # @rbs () -> untyped
      def source_line = location_value(@start, :source_line)

      # @rbs () -> untyped
      def end_file
        return file if empty?

        location_value(@finish, :end_file) || location_value(@finish, :file)
      end

      # @rbs () -> untyped
      def end_line
        return line if empty?

        location_value(@finish, :end_line) || location_value(@finish, :line)
      end

      # @rbs () -> untyped
      def end_column
        return column if empty?

        location_value(@finish, :end_column) || location_value(@finish, :column)
      end

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        {
          file: file, line: line, column: column,
          end_file: end_file, end_line: end_line, end_column: end_column,
          empty: empty?
        }
      end

      class << self
        private

        # @rbs (untyped location) -> untyped
        def boundary_start(location)
          location.is_a?(LocationSpan) ? location.start : location
        end

        # @rbs (untyped location) -> untyped
        def boundary_finish(location)
          location.is_a?(LocationSpan) ? location.finish : location
        end
      end

      private

      # @rbs (untyped location, Symbol key) -> untyped
      def location_value(location, key)
        return location.public_send(key) if location.respond_to?(key)
        return location[key] || location[key.to_s] if location.is_a?(Hash)

        nil
      end
    end
  end
end
