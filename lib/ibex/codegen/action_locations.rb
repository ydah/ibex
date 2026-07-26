# frozen_string_literal: true
# rbs_inline: enabled

require "ripper"

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
        offsets = line_offsets
        tokens = Object.const_get(:Ripper).__send__(:lex, @source)
        # @type var tokens: Array[[[Integer, Integer], Symbol, String, untyped]]
        tokens.filter_map do |position, type, token, _state|
          next unless semantic_token?(type, token)

          line, column = position
          offset = offsets.fetch(line - 1) + column
          spelling = @source.b.byteslice(offset..)&.match(/\A@(?:\$|\d+)/)&.[](0)
          [offset, spelling] if spelling
        end
      end

      # CRuby tokenizes an invalid semantic reference as an "@" ivar token
      # followed by its suffix. Other Ripper implementations can return the
      # complete spelling as the ivar token.
      # @rbs (Symbol type, String token) -> bool
      def semantic_token?(type, token)
        type == :on_ivar && (token == "@" || token.match?(/\A@(?:\$|\d+)\z/))
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
