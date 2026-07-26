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
        return unless @grammar.starts.length > 1

        entries = @automaton.entry_states.map { |name, state| "#{name.to_sym.inspect} => #{state}" }
        lines << "#{indent}ENTRY_STATES = { #{entries.join(', ')} }.freeze"
      end

      # @rbs (Array[String] lines) -> void
      def append_entry_methods(lines)
        return unless @grammar.starts.length > 1

        @grammar.starts.each do |name|
          lines << "  def parse_#{name}"
          lines << "    drive_parser(-> { next_token }, initial_state: ENTRY_STATES.fetch(:#{name}))"
          lines << "  end"
          lines << ""
        end
      end

      # @rbs () -> String
      def entry_table_fields
        return "" unless @grammar.starts.length > 1

        " initial_state: ENTRY_STATES.fetch(:#{@grammar.start}), entry_states: ENTRY_STATES,"
      end

      # @rbs () -> String
      def recovery_table_fields
        names = @grammar.recovery[:sync_tokens]
        return "" if names.empty?

        ids = names.map do |name|
          symbol = @grammar.symbol(name) || raise(Ibex::Error, "missing recovery sync token #{name}")
          symbol.id
        end
        " recovery_sync_tokens: #{ids.inspect}.freeze,"
      end
    end
  end
end
