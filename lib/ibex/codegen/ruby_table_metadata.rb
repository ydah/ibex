# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Codegen
    # Emits immutable identity and size metadata for generated parser tables.
    module RubyTableMetadata
      # @rbs @automaton: IR::Automaton
      # @rbs @grammar: IR::Grammar

      private

      # @rbs (Array[String] lines, String indent) -> void
      def append_table_metadata(lines, indent)
        lines << "#{indent}PARSER_TABLE_FORMAT_VERSION = #{Runtime::PARSER_TABLE_FORMAT_VERSION}"
        lines << "#{indent}GRAMMAR_DIGEST = #{@automaton.grammar_digest.inspect}.freeze"
        lines << "#{indent}STATE_COUNT = #{@automaton.states.length}"
        lines << "#{indent}PRODUCTION_COUNT = #{@grammar.productions.length}"
      end
    end
  end
end
