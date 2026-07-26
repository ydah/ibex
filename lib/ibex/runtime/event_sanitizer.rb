# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # Converts application-owned values into bounded, data-only event summaries.
    # rubocop:disable Metrics/ModuleLength
    module EventSanitizer
      MAX_DEPTH = 3 #: Integer
      MAX_COLLECTION_ENTRIES = 16 #: Integer
      MAX_STRING_BYTES = 256 #: Integer
      MAX_INTEGER_BITS = 64 #: Integer
      STRING_INPUT_BYTES = 1_024 #: Integer
      DATA_MAX_DEPTH = 16 #: Integer

      class << self
        # Copy a runtime payload into deeply frozen JSON data. Unknown objects are
        # summarized instead of being retained, so callers cannot smuggle mutable
        # application identities into an Event.
        # @rbs (Hash[untyped, untyped] input) -> Hash[String, untyped]
        def data(input)
          result = {} #: Hash[String, untyped]
          consumed = 0
          core_call(Hash, :each_pair, input) do |key, raw|
            break if consumed == MAX_COLLECTION_ENTRIES

            consumed += 1
            result[data_key(key)] = json_data(raw, depth: 0, seen: {})
          end
          result.freeze
        rescue StandardError
          { "unavailable" => "event_data" }.freeze
        end

        # @rbs (untyped input) -> untyped
        def value(input)
          summarize(input, depth: 0, seen: {})
        rescue StandardError
          unavailable("sanitization")
        end

        # @rbs (untyped location) -> Hash[String, untyped]?
        def location(location)
          return nil unless location

          fields = {
            "file" => location_field(location, :file),
            "line" => location_field(location, :line),
            "column" => location_field(location, :column),
            "end_line" => location_field(location, :end_line),
            "end_column" => location_field(location, :end_column)
          }
          fields.compact.transform_values { |entry| value(entry) }.freeze
        rescue StandardError
          unavailable("location")
        end

        # @rbs (untyped input) -> String
        def string(input)
          return "<unavailable>" unless core_type?(input, String)

          prefix = core_call(String, :byteslice, input, 0, STRING_INPUT_BYTES) || ""
          encoded = core_call(
            String,
            :encode,
            prefix,
            Encoding::UTF_8,
            invalid: :replace,
            undef: :replace,
            replace: "\uFFFD"
          )
          encoded_bytes = core_call(String, :bytesize, encoded)
          input_bytes = core_call(String, :bytesize, input)
          return encoded.freeze if encoded_bytes <= MAX_STRING_BYTES && input_bytes <= STRING_INPUT_BYTES

          truncate_utf8(encoded)
        rescue StandardError
          "<unavailable>"
        end

        # @rbs (untyped input) -> String
        def class_name(input)
          klass = core_call(Object, :class, input)
          name = core_call(Module, :name, klass)
          core_type?(name, String) && !core_call(String, :empty?, name) ? string(name) : "<anonymous>"
        rescue StandardError
          "<unknown>"
        end

        private

        # @rbs (untyped input, depth: Integer, seen: Hash[Integer, bool]) -> untyped
        def summarize(input, depth:, seen:)
          return input if primitive?(input)
          return bounded_integer(input) if core_type?(input, Integer)
          return finite_float(input) if core_type?(input, Float)
          return string(input) if core_type?(input, String)
          return string(core_call(Symbol, :name, input)) if core_type?(input, Symbol)
          return summarize_array(input, depth: depth, seen: seen) if core_type?(input, Array)
          return summarize_hash(input, depth: depth, seen: seen) if core_type?(input, Hash)

          { "type" => "object", "class" => class_name(input) }.freeze
        end

        # @rbs (untyped input, depth: Integer, seen: Hash[Integer, bool]) -> untyped
        def json_data(input, depth:, seen:)
          return unavailable("depth") if depth >= DATA_MAX_DEPTH
          return input if primitive?(input)
          return bounded_integer(input) if core_type?(input, Integer)
          return finite_float(input) if core_type?(input, Float)
          return string(input) if core_type?(input, String)
          return string(core_call(Symbol, :name, input)) if core_type?(input, Symbol)
          return json_array(input, depth: depth, seen: seen) if core_type?(input, Array)
          return json_hash(input, depth: depth, seen: seen) if core_type?(input, Hash)

          { "type" => "object", "class" => class_name(input) }.freeze
        end

        # @rbs (Array[untyped] input, depth: Integer, seen: Hash[Integer, bool]) -> untyped
        def summarize_array(input, depth:, seen:)
          return unavailable("depth") if depth >= MAX_DEPTH

          copy_array(input, seen: seen) do |child, nested|
            summarize(child, depth: depth + 1, seen: nested)
          end
        end

        # @rbs (Hash[untyped, untyped] input, depth: Integer, seen: Hash[Integer, bool]) -> untyped
        def summarize_hash(input, depth:, seen:)
          return unavailable("depth") if depth >= MAX_DEPTH

          identity = object_identity(input)
          return { "cycle" => true }.freeze if seen[identity]

          nested = seen.merge(identity => true)
          entries = [] #: Array[untyped]
          length = core_call(Hash, :length, input)
          core_call(Hash, :each_pair, input) do |key, child|
            break if entries.length == MAX_COLLECTION_ENTRIES

            entries << [
              summarize(key, depth: depth + 1, seen: nested),
              summarize(child, depth: depth + 1, seen: nested)
            ].freeze
          end
          summary = { "type" => "hash", "entries" => entries.freeze }
          summary["omitted"] = length - entries.length if length > entries.length
          summary.freeze
        end

        # @rbs (Array[untyped] input, depth: Integer, seen: Hash[Integer, bool]) -> untyped
        def json_array(input, depth:, seen:)
          copy_array(input, seen: seen) do |child, nested|
            json_data(child, depth: depth + 1, seen: nested)
          end
        end

        # @rbs (Hash[untyped, untyped] input, depth: Integer, seen: Hash[Integer, bool]) -> untyped
        def json_hash(input, depth:, seen:)
          identity = object_identity(input)
          return { "cycle" => true }.freeze if seen[identity]

          nested = seen.merge(identity => true)
          result = {} #: Hash[String, untyped]
          length = core_call(Hash, :length, input)
          consumed = 0
          core_call(Hash, :each_pair, input) do |key, child|
            break if consumed == MAX_COLLECTION_ENTRIES

            consumed += 1
            result[data_key(key)] = json_data(child, depth: depth + 1, seen: nested)
          end
          result["omitted"] = length - consumed if length > consumed
          result.freeze
        end

        # @rbs (Array[untyped] input, seen: Hash[Integer, bool])
        #   { (untyped, Hash[Integer, bool]) -> untyped } -> untyped
        def copy_array(input, seen:)
          identity = object_identity(input)
          return { "cycle" => true }.freeze if seen[identity]

          nested = seen.merge(identity => true)
          length = core_call(Array, :length, input)
          limit = [length, MAX_COLLECTION_ENTRIES].min
          result = Array.new(limit) do |index|
            child = core_call(Array, :fetch, input, index)
            yield(child, nested)
          end
          result << { "omitted" => length - limit }.freeze if length > limit
          result.freeze
        end

        # @rbs (untyped input) -> bool
        def primitive?(input)
          core_type?(input, NilClass) ||
            core_type?(input, TrueClass) ||
            core_type?(input, FalseClass)
        end

        # @rbs (Integer input) -> untyped
        def bounded_integer(input)
          bits = core_call(Integer, :bit_length, input)
          return input if bits <= MAX_INTEGER_BITS

          {
            "type" => "integer",
            "bits" => bits,
            "sign" => core_call(Integer, :negative?, input) ? "negative" : "positive"
          }.freeze
        end

        # @rbs (Float input) -> untyped
        def finite_float(input)
          core_call(Float, :finite?, input) ? input : string(core_call(Float, :to_s, input))
        end

        # @rbs (untyped input, Module type) -> bool
        def core_type?(input, type)
          core_call(Module, :===, type, input)
        end

        # @rbs (untyped key) -> String
        def data_key(key)
          return string(key) if core_type?(key, String)
          return string(core_call(Symbol, :name, key)) if core_type?(key, Symbol)

          "<#{class_name(key)}>"
        end

        # @rbs (String input) -> String
        def truncate_utf8(input)
          prefix = core_call(String, :byteslice, input, 0, MAX_STRING_BYTES - 3) || ""
          until core_call(String, :valid_encoding?, prefix)
            prefix = core_call(String, :byteslice, prefix, 0, core_call(String, :bytesize, prefix) - 1)
          end
          "#{prefix}\u2026".freeze
        end

        # @rbs (untyped input) -> Integer
        def object_identity(input)
          core_call(BasicObject, :__id__, input)
        end

        # @rbs (untyped location, Symbol field) -> untyped
        def location_field(location, field)
          if core_type?(location, Hash)
            return core_call(Hash, :fetch, location, field) do
              core_call(Hash, :fetch, location, core_call(Symbol, :name, field), nil)
            end
          end
          return unless core_call(Kernel, :respond_to?, location, field)

          core_call(Kernel, :public_send, location, field)
        rescue StandardError
          nil
        end

        # @rbs (String reason) -> Hash[String, untyped]
        def unavailable(reason)
          { "unavailable" => reason.freeze }.freeze
        end

        # @rbs (Module owner, Symbol method_name, untyped receiver, *untyped args, **untyped keywords)
        #   ?{ (*untyped) -> untyped } -> untyped
        def core_call(owner, method_name, receiver, ...)
          owner.instance_method(method_name).bind(receiver).call(...)
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
