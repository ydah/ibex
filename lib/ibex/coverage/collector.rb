# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Coverage
    # Strictly turns one or more complete parse sessions into a coverage report.
    class Collector
      # @rbs!
      #   type json_value = String | Integer | Float | bool | nil | Array[json_value] | Hash[String, json_value]

      # @rbs @grammar_digest: String?
      # @rbs @table_format_version: Integer?
      # @rbs @state_count: Integer?
      # @rbs @production_count: Integer?
      # @rbs @sessions: Integer
      # @rbs @event_count: Integer
      # @rbs @state_hits: Hash[Integer, Integer]
      # @rbs @production_hits: Hash[Integer, Integer]
      # @rbs @in_session: bool
      # @rbs @expected_sequence: Integer

      # @rbs () -> void
      def initialize
        @grammar_digest = nil
        @table_format_version = nil
        @state_count = nil
        @production_count = nil
        @sessions = 0
        @event_count = 0
        @state_hits = Hash.new(0)
        @production_hits = Hash.new(0)
        @in_session = false
        @expected_sequence = 1
      end

      # @rbs (String path) -> Report
      def self.collect_file(path)
        collector = new
        EventStream.each_file(path) do |document, line|
          collector.consume(document, source: path, line: line)
        end
        collector.finish(source: path)
      end

      # @rbs (Hash[String, json_value] document, source: String, line: Integer) -> void
      def consume(document, source:, line:)
        event = document.fetch("event")
        sequence = document.fetch("sequence")
        data = document.fetch("data")
        unless event.is_a?(String) && data.is_a?(Hash) && data.keys.all?(String)
          invalid(source, line, "event document contains invalid session data")
        end
        event_data = data #: Hash[String, json_value]
        if event == "start"
          start_session(event_data, sequence, source, line)
        else
          consume_session_event(event, event_data, sequence, source, line)
        end
        @event_count += 1
      end

      # @rbs (source: String) -> Report
      def finish(source:)
        invalid(source, 1, "event stream ended before accept or reject") if @in_session
        invalid(source, 1, "event stream does not contain a parse session") if @sessions.zero?
        Report.new(
          grammar_digest: required_metadata(@grammar_digest),
          table_format_version: required_metadata(@table_format_version),
          state_count: required_metadata(@state_count),
          production_count: required_metadata(@production_count),
          sessions: @sessions,
          event_count: @event_count,
          state_hits: @state_hits,
          production_hits: @production_hits
        )
      rescue ArgumentError => e
        raise Ibex::Error, "#{source}:1:1: #{e.message}"
      end

      private

      # @rbs (Hash[String, json_value] data, json_value sequence, String source, Integer line) -> void
      def start_session(data, sequence, source, line)
        invalid(source, line, "new start event before prior session ended") if @in_session
        invalid(source, line, "start event sequence must be 1") unless sequence == 1

        metadata, initial_state = session_metadata(data, source, line)
        establish_metadata(metadata, source, line)
        validate_metadata!(source, line)
        hit_state(initial_state, source, line)
        @sessions += 1
        @in_session = true
        @expected_sequence = 2
      end

      # @rbs (String event, Hash[String, json_value] data, json_value sequence, String source, Integer line) -> void
      def consume_session_event(event, data, sequence, source, line)
        invalid(source, line, "event appears outside a parse session") unless @in_session
        unless sequence == @expected_sequence
          invalid(source, line, "expected event sequence #{@expected_sequence}, got #{sequence.inspect}")
        end

        case event
        when "shift", "recover" then hit_state(data["state"], source, line)
        when "reduce"
          hit_production(data["production_id"], source, line)
          hit_state(data["goto_state"], source, line)
        end
        if %w[accept reject].include?(event)
          @in_session = false
          @expected_sequence = 1
        else
          @expected_sequence += 1
        end
      end

      # @rbs (Hash[String, json_value] data, String source, Integer line)
      #   -> [[String, Integer, Integer, Integer], Integer]
      def session_metadata(data, source, line)
        digest = data["grammar_digest"]
        format = data["table_format_version"]
        states = data["state_count"]
        productions = data["production_count"]
        initial_state = data["initial_state"]
        unless digest.is_a?(String) && format.is_a?(Integer) && states.is_a?(Integer) &&
               productions.is_a?(Integer) && initial_state.is_a?(Integer)
          invalid(source, line, "start event lacks generated parser coverage metadata")
        end
        [[digest, format, states, productions], initial_state]
      end

      # @rbs ([String, Integer, Integer, Integer] metadata, String source, Integer line) -> void
      def establish_metadata(metadata, source, line)
        unless @grammar_digest
          @grammar_digest, @table_format_version, @state_count, @production_count = metadata
          return
        end

        expected = [@grammar_digest, @table_format_version, @state_count, @production_count]
        invalid(source, line, "parse sessions use different parser metadata") unless metadata == expected
      end

      # @rbs (String source, Integer line) -> void
      def validate_metadata!(source, line)
        Report.new(
          grammar_digest: required_metadata(@grammar_digest),
          table_format_version: required_metadata(@table_format_version),
          state_count: required_metadata(@state_count),
          production_count: required_metadata(@production_count),
          sessions: 1,
          event_count: 1,
          state_hits: {},
          production_hits: {}
        )
      rescue ArgumentError => e
        invalid(source, line, e.message)
      end

      # @rbs (json_value id, String source, Integer line) -> void
      def hit_state(id, source, line)
        total = required_metadata(@state_count)
        invalid(source, line, "state id #{id.inspect} is outside 0...#{total}") unless valid_id?(id, total)
        state_id = id #: Integer
        increment(@state_hits, state_id, "state", source, line)
      end

      # @rbs (json_value id, String source, Integer line) -> void
      def hit_production(id, source, line)
        total = required_metadata(@production_count)
        invalid(source, line, "production id #{id.inspect} is outside 0...#{total}") unless valid_id?(id, total)
        production_id = id #: Integer
        increment(@production_hits, production_id, "production", source, line)
      end

      # @rbs (json_value id, Integer total) -> bool
      def valid_id?(id, total)
        id.is_a?(Integer) && id >= 0 && id < total
      end

      # @rbs (Hash[Integer, Integer] hits, Integer id, String kind, String source, Integer line) -> void
      def increment(hits, id, kind, source, line)
        count = hits[id] + 1
        invalid(source, line, "#{kind} hit count exceeds the supported count") if count > Report::MAX_COUNT
        hits[id] = count
      end

      # @rbs [T] (T? value) -> T
      def required_metadata(value)
        value || raise(ArgumentError, "coverage metadata is unavailable")
      end

      # @rbs (String source, Integer line, String message) -> bot
      def invalid(source, line, message)
        raise Ibex::Error, "#{source}:#{line}:1: #{message}"
      end
    end
  end
end
