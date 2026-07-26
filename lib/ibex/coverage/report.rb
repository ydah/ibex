# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require_relative "../error"

module Ibex
  module Coverage
    # Versioned, mergeable runtime coverage result.
    class Report
      IDENTIFIER = "runtime-coverage" #: String
      SCHEMA_VERSION = 1 #: Integer
      MAX_DOCUMENT_BYTES = 16_777_216 #: Integer
      MAX_TOTAL = 1_000_000 #: Integer
      MAX_COUNT = 9_223_372_036_854_775_807 #: Integer
      ROOT_KEYS = %w[events grammar_digest ibex_coverage production_hits schema_version sessions state_hits
                     table_format_version totals].freeze #: Array[String]
      TOTAL_KEYS = %w[productions states].freeze #: Array[String]
      HIT_KEYS = %w[count id].freeze #: Array[String]

      attr_reader :grammar_digest #: String
      attr_reader :table_format_version #: Integer
      attr_reader :state_count #: Integer
      attr_reader :production_count #: Integer
      attr_reader :sessions #: Integer
      attr_reader :event_count #: Integer
      attr_reader :state_hits #: Hash[Integer, Integer]
      attr_reader :production_hits #: Hash[Integer, Integer]

      # rubocop:disable Layout/LineLength
      # @rbs (grammar_digest: String, table_format_version: Integer, state_count: Integer, production_count: Integer, sessions: Integer, event_count: Integer, state_hits: Hash[Integer, Integer], production_hits: Hash[Integer, Integer]) -> void
      def initialize(grammar_digest:, table_format_version:, state_count:, production_count:, sessions:, event_count:,
                     state_hits:, production_hits:)
        @grammar_digest = validate_digest(grammar_digest)
        @table_format_version = positive_integer(table_format_version, "table_format_version")
        @state_count = total_integer(state_count, "state total", minimum: 1)
        @production_count = total_integer(production_count, "production total", minimum: 0)
        @sessions = positive_integer(sessions, "sessions")
        @event_count = positive_integer(event_count, "events")
        raise ArgumentError, "events must be at least sessions" if @event_count < @sessions

        @state_hits = validate_hits(state_hits, @state_count, "state").freeze
        @production_hits = validate_hits(production_hits, @production_count, "production").freeze
        validate_event_bounds
        freeze
      end
      # rubocop:enable Layout/LineLength

      # @rbs () -> Hash[String, untyped]
      def to_h
        {
          "ibex_coverage" => IDENTIFIER,
          "schema_version" => SCHEMA_VERSION,
          "grammar_digest" => @grammar_digest,
          "table_format_version" => @table_format_version,
          "totals" => { "states" => @state_count, "productions" => @production_count },
          "sessions" => @sessions,
          "events" => @event_count,
          "state_hits" => hit_documents(@state_hits),
          "production_hits" => hit_documents(@production_hits)
        }
      end

      # @rbs (*untyped) -> String
      def to_json(*)
        "#{JSON.pretty_generate(to_h)}\n"
      end

      # @rbs (String path) -> Report
      def self.load_file(path)
        size = File.size(path)
        if size > MAX_DOCUMENT_BYTES
          raise Ibex::Error, "#{path}:1:1: coverage document exceeds #{MAX_DOCUMENT_BYTES} bytes"
        end

        source = File.binread(path)
        if source.bytesize > MAX_DOCUMENT_BYTES
          raise Ibex::Error, "#{path}:1:1: coverage document exceeds #{MAX_DOCUMENT_BYTES} bytes"
        end

        source.force_encoding(Encoding::UTF_8)
        raise Ibex::Error, "#{path}:1:1: coverage document is not valid UTF-8" unless source.valid_encoding?

        value = JSON.parse(source, max_nesting: 16, allow_nan: false)
        from_h(value, source: path)
      rescue JSON::ParserError => e
        raise Ibex::Error, "#{path}:1:1: invalid coverage JSON: #{e.message}"
      end

      # @rbs (untyped value, source: String) -> Report
      def self.from_h(value, source:)
        document = string_hash(value, source, "coverage document")
        invalid(source, "coverage object has unknown or missing fields") unless document.keys.sort == ROOT_KEYS
        valid_schema = document["ibex_coverage"] == IDENTIFIER &&
                       document["schema_version"] == SCHEMA_VERSION
        invalid(source, "unsupported coverage schema") unless valid_schema
        totals = string_hash(document["totals"], source, "coverage totals")
        invalid(source, "coverage totals have unknown or missing fields") unless totals.keys.sort == TOTAL_KEYS

        state_count = totals["states"]
        production_count = totals["productions"]
        new(
          grammar_digest: document["grammar_digest"],
          table_format_version: document["table_format_version"],
          state_count: state_count,
          production_count: production_count,
          sessions: document["sessions"],
          event_count: document["events"],
          state_hits: parse_hits(document["state_hits"], state_count, source, "state"),
          production_hits: parse_hits(document["production_hits"], production_count, source, "production")
        )
      rescue ArgumentError => e
        raise Ibex::Error, "#{source}:1:1: #{e.message}"
      end

      # @rbs (Array[Report] reports) -> Report
      def self.merge(reports)
        raise ArgumentError, "at least one coverage report is required" if reports.empty?

        first = reports.first
        reports.drop(1).each { |report| ensure_compatible(first, report) }
        new(
          grammar_digest: first.grammar_digest,
          table_format_version: first.table_format_version,
          state_count: first.state_count,
          production_count: first.production_count,
          sessions: checked_sum(reports.map(&:sessions), "sessions"),
          event_count: checked_sum(reports.map(&:event_count), "events"),
          state_hits: merge_hits(reports.map(&:state_hits), "state"),
          production_hits: merge_hits(reports.map(&:production_hits), "production")
        )
      end

      private

      # @rbs (untyped input) -> String
      def validate_digest(input)
        valid = input.is_a?(String) && input.match?(/\Asha256:[0-9a-f]{64}\z/)
        return input.dup.freeze if valid

        raise ArgumentError, "grammar_digest must be a full lowercase SHA-256 digest"
      end

      # @rbs (untyped input, String name) -> Integer
      def positive_integer(input, name)
        return input if input.is_a?(Integer) && input.positive? && input <= MAX_COUNT

        raise ArgumentError, "#{name} must be a bounded positive integer"
      end

      # @rbs (untyped input, String name, minimum: Integer) -> Integer
      def total_integer(input, name, minimum:)
        return input if input.is_a?(Integer) && input >= minimum && input <= MAX_TOTAL

        raise ArgumentError, "#{name} must be between #{minimum} and #{MAX_TOTAL}"
      end

      # @rbs (Hash[Integer, Integer] input, Integer total, String kind) -> Hash[Integer, Integer]
      def validate_hits(input, total, kind)
        input.to_h do |id, count|
          unless id.is_a?(Integer) && id >= 0 && id < total
            raise ArgumentError, "#{kind} hit id #{id.inspect} is outside 0...#{total}"
          end

          [id, positive_integer(count, "#{kind} hit count")]
        end.sort.to_h
      end

      # @rbs (Hash[Integer, Integer] hits) -> Array[Hash[String, Integer]]
      def hit_documents(hits)
        hits.map { |id, count| { "id" => id, "count" => count } }
      end

      # @rbs () -> void
      def validate_event_bounds
        raise ArgumentError, "state hit counts exceed events" if @state_hits.values.sum > @event_count
        return unless @production_hits.values.sum > @event_count

        raise ArgumentError, "production hit counts exceed events"
      end

      class << self
        private

        # @rbs (untyped value, String source, String name) -> Hash[String, untyped]
        def string_hash(value, source, name)
          return value if value.is_a?(Hash) && value.keys.all?(String)

          invalid(source, "#{name} must be an object")
        end

        # @rbs (untyped value, untyped total, String source, String kind) -> Hash[Integer, Integer]
        def parse_hits(value, total, source, kind)
          invalid(source, "#{kind}_hits must be an array") unless value.is_a?(Array)
          hits = {} #: Hash[Integer, Integer]
          previous = -1
          value.each do |entry|
            id, count = parse_hit(entry, total, previous, source, kind)
            hits[id] = count
            previous = id
          end
          hits
        end

        # @rbs (untyped entry, untyped total, Integer previous, String source, String kind) -> [Integer, Integer]
        def parse_hit(entry, total, previous, source, kind)
          hit = string_hash(entry, source, "#{kind} hit")
          invalid(source, "#{kind} hit has unknown or missing fields") unless hit.keys.sort == HIT_KEYS
          id = hit["id"]
          count = hit["count"]
          unless id.is_a?(Integer) && id > previous
            invalid(source, "#{kind} hits must have unique, ascending integer ids")
          end
          unless total.is_a?(Integer) && id >= 0 && id < total
            invalid(source, "#{kind} hit id is outside the declared total")
          end
          unless count.is_a?(Integer) && count.positive? && count <= MAX_COUNT
            invalid(source, "#{kind} hit count must be positive")
          end
          [id, count]
        end

        # @rbs (Report expected, Report actual) -> void
        def ensure_compatible(expected, actual)
          fields = %i[grammar_digest table_format_version state_count production_count]
          mismatch = fields.find { |field| expected.public_send(field) != actual.public_send(field) }
          return unless mismatch

          raise ArgumentError, "coverage reports have different #{mismatch}"
        end

        # @rbs (Array[Integer] values, String name) -> Integer
        def checked_sum(values, name)
          total = values.sum
          raise ArgumentError, "merged #{name} exceed the supported count" if total > MAX_COUNT

          total
        end

        # @rbs (Array[Hash[Integer, Integer]] collections, String kind) -> Hash[Integer, Integer]
        def merge_hits(collections, kind)
          result = Hash.new(0) #: Hash[Integer, Integer]
          collections.each do |hits|
            hits.each do |id, count|
              result[id] += count
              raise ArgumentError, "merged #{kind} hit count exceeds the supported count" if result[id] > MAX_COUNT
            end
          end
          result
        end

        # @rbs (String source, String message) -> bot
        def invalid(source, message)
          raise Ibex::Error, "#{source}:1:1: #{message}"
        end
      end
    end
  end
end
