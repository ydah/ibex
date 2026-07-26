# frozen_string_literal: true

require_relative "renderer"

module Ibex
  module ErrorMessages
    # @rbs (IR::Automaton automaton, ?existing: Document?, ?max_tokens: Integer,
    #   ?max_configurations: Integer) -> String
    def render(automaton, existing: nil, max_tokens: SentenceSearch::DEFAULT_MAX_TOKENS,
               max_configurations: SentenceSearch::DEFAULT_MAX_CONFIGURATIONS)
      update(
        automaton, existing: existing, max_tokens: max_tokens, max_configurations: max_configurations
      ).source
    end
    module_function :render

    # @rbs (IR::Automaton automaton, ?existing: Document?, ?max_tokens: Integer,
    #   ?max_configurations: Integer) -> Update
    def update(automaton, existing: nil, max_tokens: SentenceSearch::DEFAULT_MAX_TOKENS,
               max_configurations: SentenceSearch::DEFAULT_MAX_CONFIGURATIONS)
      document = existing || Document.new(entries: [])
      search = SentenceSearch.new(
        automaton, max_tokens: max_tokens, max_configurations: max_configurations
      )
      witnesses = search.all
      classifications = { uncovered: [], unreachable: [], moved: [] } #: Hash[Symbol, Array[String]]
      next_id = next_error_id(document)
      entries, covered, next_id = update_existing_entries(
        document, search, witnesses, classifications, next_id
      )
      add_uncovered_entries(entries, covered, witnesses, classifications[:uncovered], next_id)
      entries.sort_by! { |entry| entry_sort_key(entry) }
      Update.new(
        source: render_entries(automaton, entries),
        uncovered: classifications[:uncovered],
        unreachable: classifications[:unreachable],
        moved: classifications[:moved]
      )
    end
    module_function :update

    # @rbs (Array[Entry] entries, Hash[Integer, bool] covered,
    #   Hash[Integer, SentenceSearch::Witness] witnesses, Array[String] uncovered, Integer next_id) -> void
    def add_uncovered_entries(entries, covered, witnesses, uncovered, next_id)
      witnesses.each do |state, witness|
        next if covered[state]

        error_id = format_error_id(next_id)
        next_id += 1
        entries << Entry.new(
          state: state, status: :active, message: nil, line: 1,
          sentence: witness.tokens, error_id: error_id, entry: witness.entry
        )
        uncovered << "#{error_id} state #{state}: #{witness.tokens.join(' ')}"
      end
    end

    # @rbs (Document document, SentenceSearch search, Hash[Integer, SentenceSearch::Witness] witnesses,
    #   Hash[Symbol, Array[String]] classifications, Integer next_id) ->
    #   [Array[Entry], Hash[Integer, bool], Integer]
    def update_existing_entries(document, search, witnesses, classifications, next_id)
      return migrate_legacy_entries(document, witnesses, classifications, next_id) if document.version == 1

      entries = [] #: Array[Entry]
      covered = {} #: Hash[Integer, bool]
      document.entries.each do |entry|
        if entry.sentence
          next_id = update_sentence_entry(
            entry, search, entries, covered, classifications, next_id
          )
        else
          entries << with_error_id(entry, next_id)
          next_id += 1 unless entry.error_id
        end
      end
      [entries, covered, next_id]
    end

    # @rbs (Entry entry, SentenceSearch search, Array[Entry] entries, Hash[Integer, bool] covered,
    #   Hash[Symbol, Array[String]] classifications, Integer next_id) -> Integer
    def update_sentence_entry(entry, search, entries, covered, classifications, next_id)
      error_id = entry.error_id || format_error_id(next_id)
      next_id += 1 unless entry.error_id
      sentence = entry.sentence || raise(Ibex::Error, "missing error sentence")
      state = search.state_for(sentence, entry: entry.entry)
      unless state
        entries << Entry.new(
          state: entry.state, status: :unreachable, message: entry.message, line: entry.line,
          sentence: sentence, error_id: error_id, entry: entry.entry
        )
        classifications[:unreachable] << "#{error_id}: #{sentence.join(' ')}"
        return next_id
      end

      classifications[:moved] << "#{error_id}: state #{entry.state} -> #{state}" if entry.state && entry.state != state
      covered[state] = true
      entries << Entry.new(
        state: state, status: :active, message: entry.message, line: entry.line,
        sentence: sentence, error_id: error_id, entry: entry.entry
      )
      next_id
    end

    # @rbs (Document document, Hash[Integer, SentenceSearch::Witness] witnesses,
    #   Hash[Symbol, Array[String]] classifications, Integer next_id) ->
    #   [Array[Entry], Hash[Integer, bool], Integer]
    def migrate_legacy_entries(document, witnesses, classifications, next_id)
      by_state = document.entries.to_h { |entry| [entry.state, entry] }
      entries = [] #: Array[Entry]
      covered = {} #: Hash[Integer, bool]
      witnesses.each do |state, witness|
        previous = by_state.delete(state)
        error_id = format_error_id(next_id)
        next_id += 1
        entries << Entry.new(
          state: state, status: :active, message: previous&.message, line: previous&.line || 1,
          sentence: witness.tokens, error_id: error_id, entry: witness.entry
        )
        covered[state] = true
        classifications[:uncovered] << "#{error_id} state #{state}: #{witness.tokens.join(' ')}" unless previous
      end
      by_state.values.sort_by { |entry| entry.state || -1 }.each do |entry|
        error_id = format_error_id(next_id)
        next_id += 1
        entries << Entry.new(
          state: entry.state, status: :removed, message: entry.message, line: entry.line, error_id: error_id
        )
        classifications[:unreachable] << "#{error_id}: legacy state #{entry.state}"
      end
      [entries, covered, next_id]
    end

    # @rbs (Entry entry, Integer next_id) -> Entry
    def with_error_id(entry, next_id)
      Entry.new(
        state: entry.state, status: entry.status, message: entry.message, line: entry.line,
        sentence: entry.sentence, error_id: entry.error_id || format_error_id(next_id), entry: entry.entry
      )
    end

    # @rbs (Document document) -> Integer
    def next_error_id(document)
      maximum = document.entries.filter_map do |entry|
        match = entry.error_id&.match(/\AE([0-9]{4,})\z/)
        match && Integer(match[1] || "0", 10)
      end.max
      (maximum || 0) + 1
    end

    # @rbs (Integer number) -> String
    def format_error_id(number)
      format("E%04d", number)
    end

    # @rbs (Entry entry) -> [Integer, Integer, String]
    def entry_sort_key(entry)
      rank = { active: 0, unreachable: 1, removed: 2 }.fetch(entry.status)
      [rank, entry.state || (1 << 62), entry.error_id || ""]
    end

    module_function :add_uncovered_entries, :update_existing_entries, :update_sentence_entry, :migrate_legacy_entries,
                    :with_error_id, :next_error_id, :format_error_id, :entry_sort_key

    class << self
      private :add_uncovered_entries, :update_existing_entries, :update_sentence_entry, :migrate_legacy_entries,
              :with_error_id, :next_error_id, :format_error_id, :entry_sort_key
    end
  end
end
