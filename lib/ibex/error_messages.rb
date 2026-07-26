# frozen_string_literal: true
# rbs_inline: enabled

require_relative "error"

module Ibex
  # Parses, validates, and deterministically updates example-keyed syntax
  # error messages.
  module ErrorMessages
    HEADER_V1 = "# ibex-messages v1"
    HEADER = "# ibex-messages v2"

    # One active or archived error-sentence entry with its source line.
    class Entry
      attr_reader :state #: Integer?
      attr_reader :status #: :active | :unreachable | :removed
      attr_reader :message #: String?
      attr_reader :line #: Integer
      attr_reader :sentence #: Array[String]?
      attr_reader :error_id #: String?
      attr_reader :entry #: String?

      # @rbs (state: Integer?, status: :active | :unreachable | :removed, message: String?, line: Integer,
      #   ?sentence: Array[String]?, ?error_id: String?, ?entry: String?) -> void
      def initialize(state:, status:, message:, line:, sentence: nil, error_id: nil, entry: nil)
        @state = state
        @status = status
        @message = message&.freeze
        @line = line
        @sentence = sentence&.dup&.freeze
        @error_id = error_id&.freeze
        @entry = entry&.freeze
        freeze
      end
    end

    # Immutable parsed messages document.
    class Document
      attr_reader :version #: Integer
      attr_reader :entries #: Array[Entry]

      # @rbs (entries: Array[Entry], ?version: Integer) -> void
      def initialize(entries:, version: 2)
        @version = version
        @entries = entries.freeze
        freeze
      end
    end

    # Deterministic update output and review classifications.
    class Update
      attr_reader :source #: String
      attr_reader :uncovered #: Array[String]
      attr_reader :unreachable #: Array[String]
      attr_reader :moved #: Array[String]

      # @rbs (source: String, uncovered: Array[String], unreachable: Array[String], moved: Array[String]) -> void
      def initialize(source:, uncovered:, unreachable:, moved:)
        @source = source.freeze
        @uncovered = uncovered.freeze
        @unreachable = unreachable.freeze
        @moved = moved.freeze
        freeze
      end
    end

    require_relative "error_messages/parser"
    require_relative "error_messages/sentence_search"

    # @rbs (String source, file: String) -> Document
    def parse(source, file:)
      Parser.new(source, file: file).parse
    end
    module_function :parse

    # @rbs (String path) -> Document
    def load(path)
      parse(File.binread(path), file: path)
    end
    module_function :load

    # @rbs (IR::Automaton automaton) -> Array[IR::AutomatonState]
    def error_states(automaton)
      terminals = ordinary_terminals(automaton)
      automaton.states.select do |state|
        terminals.any? { |terminal| error_action?(state.actions[terminal.id] || state.default_action) }
      end.sort_by(&:id)
    end
    module_function :error_states

    # @rbs (Document document, IR::Automaton automaton, file: String) -> Hash[Integer, String]
    def messages_for(document, automaton, file:)
      records_for(document, automaton, file: file).transform_values { |record| record.fetch(:message) }.freeze
    end
    module_function :messages_for

    # @rbs (Document document, IR::Automaton automaton, file: String) ->
    #   Hash[Integer, { id: String, message: String }]
    def records_for(document, automaton, file:)
      return legacy_records_for(document, automaton, file: file) if document.version == 1

      search = SentenceSearch.new(automaton)
      records = {} #: Hash[Integer, { id: String, message: String }]
      document.entries.each do |entry|
        next unless entry.status == :active && entry.message

        sentence = entry.sentence || raise(Ibex::Error, "missing active error sentence")
        state = search.state_for(sentence, entry: entry.entry)
        unless state
          fail_at(file, entry.line, 1,
                  "error sentence no longer reaches a syntax error; run `ibex errors --update`")
        end
        if records[state]
          fail_at(file, entry.line, 1,
                  "multiple messages reach error state #{state}; run `ibex errors --update`")
        end

        error_id = entry.error_id || raise(Ibex::Error, "missing error id")
        records[state] = { id: error_id, message: entry.message }
      end
      records.sort.to_h.freeze
    end
    module_function :records_for

    # @rbs (Document document, IR::Automaton automaton, file: String) ->
    #   Hash[Integer, { id: String, message: String }]
    def legacy_records_for(document, automaton, file:)
      valid = error_states(automaton).to_h { |state| [state.id, true] }
      records = {} #: Hash[Integer, { id: String, message: String }]
      document.entries.each do |entry|
        next if entry.status == :removed || !entry.message

        state = entry.state || raise(Ibex::Error, "missing legacy error state")
        unless valid[state]
          fail_at(file, entry.line, 1,
                  "unknown error state #{state} for current automaton; run `ibex errors --update`")
        end
        records[state] = { id: format_error_id(state + 1), message: entry.message }
      end
      records.sort.to_h.freeze
    end

    # @rbs (IR::Automaton automaton) -> Array[IR::GrammarSymbol]
    def ordinary_terminals(automaton)
      automaton.grammar.terminals.reject { |terminal| terminal.name == "error" }
    end

    # @rbs (IR::parser_action? action) -> bool
    def error_action?(action)
      action.nil? || action[:type].to_sym == :error
    end

    # @rbs (String file, Integer line, Integer column, String message) -> bot
    def fail_at(file, line, column, message)
      raise Ibex::Error, "#{file}:#{line}:#{column}: #{message}"
    end
    module_function :legacy_records_for, :ordinary_terminals, :error_action?, :fail_at

    class << self
      private :legacy_records_for, :ordinary_terminals, :error_action?, :fail_at
    end
  end
end

require_relative "error_messages/update"
