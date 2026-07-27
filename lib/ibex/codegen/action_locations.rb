# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Codegen
    # Rewrites semantic-location expressions without touching Ruby literals,
    # comments, heredoc bodies, or ordinary instance/class variables.
    class ActionLocations
      # @rbs @source: String
      # @rbs @maximum: Integer
      # @rbs @location: IR::location

      # @rbs (String source, maximum: Integer, location: IR::location) -> void
      def initialize(source, maximum:, location:)
        @source = source
        @maximum = maximum
        @location = location
      end

      # @rbs () -> String
      def rewrite
        return @source.b.dup.force_encoding(@source.encoding) unless @source.match?(/@(?:\$|\d+)/)

        replacements = semantic_references.map do |offset, spelling|
          [offset, spelling.bytesize, replacement_for(spelling)]
        end #: Array[[Integer, Integer, String]]
        rewritten = @source.b.dup
        replacements.reverse_each { |offset, length, replacement| rewritten[offset, length] = replacement }
        rewritten.force_encoding(@source.encoding)
      end

      private

      # @rbs () -> Array[[Integer, String]]
      def semantic_references
        require "ripper"

        offsets = line_offsets
        tokens = Object.const_get(:Ripper).__send__(:lex, lexable_source)
        # @type var tokens: Array[[[Integer, Integer], Symbol, String, untyped]]
        tokens.filter_map do |position, type, _token, _state|
          next unless type == :on_ident

          line, column = position
          offset = offsets.fetch(line - 1) + column
          spelling = @source.b.byteslice(offset..)&.match(/\A@(?:\$|\d+)/)&.[](0)
          [offset, spelling] if spelling
        end
      end

      # Give every Ripper implementation syntactically valid input while
      # preserving byte offsets and lexical string/comment boundaries.
      # @rbs () -> String
      def lexable_source
        @source.gsub(/@(?:\$|\d+)/) { |spelling| "_" * spelling.bytesize }
      end

      # @rbs () -> Array[Integer]
      def line_offsets
        offset = 0
        @source.lines.map do |line|
          current = offset
          offset += line.bytesize
          current
        end
      end

      # @rbs (String spelling) -> String
      def replacement_for(spelling)
        return "_ibex_location" if spelling == "@$"

        index = spelling.delete_prefix("@").to_i
        if index.zero? || index > @maximum
          raise Ibex::Error,
                "#{@location[:file]}:#{@location[:line]}:#{@location[:column]}: " \
                "semantic location #{spelling} is outside 1..#{@maximum}"
        end

        "_ibex_locations[#{index - 1}]"
      end
    end
  end
end
