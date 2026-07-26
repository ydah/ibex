# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require_relative "../error"
require_relative "../runtime/event"
require_relative "runtime_event_validator"

module Ibex
  module Coverage
    # Bounded reader for the public runtime-event JSON Lines protocol.
    module EventStream
      # @rbs!
      #   interface _CoverageEventInput
      #     def gets: (Integer) -> String?
      #   end

      MAX_LINE_BYTES = 1_048_576 #: Integer
      MAX_NESTING = 32 #: Integer
      ROOT_KEYS = %w[data event ibex_runtime_event schema_version sequence].freeze #: Array[String]
      EVENT_TYPES = %w[start shift reduce error recover discard accept reject].freeze #: Array[String]

      class << self
        # @rbs (String path) { (Hash[String, untyped], Integer) -> void } -> void
        def each_file(path, &block)
          File.open(path, "rb") { |input| each_io(input, source: path, &block) }
        end

        # @rbs (_CoverageEventInput input, source: String)
        #   { (Hash[String, untyped], Integer) -> void } -> void
        def each_io(input, source:, &block)
          line_number = 0
          while (line = input.gets(MAX_LINE_BYTES + 1))
            line_number += 1
            reject_oversized_line(line, source, line_number)
            document = parse_line(line, source, line_number)
            validate_envelope(document, source, line_number)
            block.call(document, line_number)
          end
          raise_invalid(source, 1, "event stream is empty") if line_number.zero?
        end

        private

        # @rbs (String line, String source, Integer line_number) -> void
        def reject_oversized_line(line, source, line_number)
          return if line.bytesize <= MAX_LINE_BYTES

          raise_invalid(source, line_number, "event line exceeds #{MAX_LINE_BYTES} bytes")
        end

        # @rbs (String line, String source, Integer line_number) -> Hash[String, untyped]
        def parse_line(line, source, line_number)
          text = line.dup.force_encoding(Encoding::UTF_8)
          raise_invalid(source, line_number, "event line is not valid UTF-8") unless text.valid_encoding?

          value = JSON.parse(text, max_nesting: MAX_NESTING, allow_nan: false)
          return value if value.is_a?(Hash) && value.keys.all?(String)

          raise_invalid(source, line_number, "event line must be a JSON object")
        rescue JSON::ParserError => e
          raise_invalid(source, line_number, "invalid event JSON: #{e.message}")
        end

        # @rbs (Hash[String, untyped] document, String source, Integer line_number) -> void
        def validate_envelope(document, source, line_number)
          unless document.keys.sort == ROOT_KEYS
            raise_invalid(source, line_number, "event object has unknown or missing fields")
          end
          unless document["ibex_runtime_event"] == Runtime::Event::IDENTIFIER &&
                 document["schema_version"] == Runtime::Event::SCHEMA_VERSION
            raise_invalid(source, line_number, "unsupported runtime event schema")
          end
          sequence = document["sequence"]
          raise_invalid(source, line_number, "event sequence must be positive") unless positive_integer?(sequence)
          unless EVENT_TYPES.include?(document["event"])
            raise_invalid(source, line_number, "unknown runtime event type")
          end
          raise_invalid(source, line_number, "event data must be an object") unless document["data"].is_a?(Hash)
          return if RuntimeEventValidator.valid?(document)

          raise_invalid(source, line_number, "event data does not match the runtime-event v1 schema")
        end

        # @rbs (untyped value) -> bool
        def positive_integer?(value)
          value.is_a?(Integer) && value.positive?
        end

        # @rbs (String source, Integer line_number, String message) -> bot
        def raise_invalid(source, line_number, message)
          raise Ibex::Error, "#{source}:#{line_number}:1: #{message}"
        end
      end
    end
  end
end
