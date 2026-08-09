# frozen_string_literal: true

module Ibex
  module IR
    module Validator
      # @rbs!
      #   type json_value = String | Integer | Float | bool | nil | Array[json_value] | Hash[String, json_value]
      #   type json_object = Hash[String, json_value]

      # Shared JSON-shape checks for the two version-1 IR documents.
      class Base
        POSITION = "(ir):1:1"

        private

        # @rbs (json_value value, String path, Array[String] required, ?Array[String] optional) -> json_object
        def record(value, path, required, optional = [])
          value = object(value, path)
          missing = required.reject { |key| value.key?(key) }
          invalid(path, "is missing required field #{missing.first.inspect}") unless missing.empty?
          unknown = value.keys - required - optional
          invalid(path, "has unsupported field #{unknown.first.inspect}") unless unknown.empty?
          value
        end

        # @rbs (json_value value, String path) -> json_object
        def object(value, path)
          if value.is_a?(Hash)
            object = value #: json_object
            return object
          end

          invalid(path, "must be an object")
        end

        # @rbs (json_value value, String path) -> Array[json_value]
        def array(value, path)
          if value.is_a?(Array)
            array = value #: Array[json_value]
            return array
          end

          invalid(path, "must be an array")
        end

        # @rbs (json_value value, String path) -> String
        def string(value, path)
          return value if value.is_a?(String)

          invalid(path, "must be a string")
        end

        # @rbs (json_value value, String path) -> String
        def nonempty_string(value, path)
          value = string(value, path)
          invalid(path, "must not be empty") if value.empty?
          value
        end

        # @rbs (json_value value, String path) -> Integer
        def integer(value, path)
          return value if value.is_a?(Integer)

          invalid(path, "must be an integer")
        end

        # @rbs (json_value value, String path) -> Integer
        def nonnegative_integer(value, path)
          value = integer(value, path)
          invalid(path, "must be greater than or equal to 0") if value.negative?
          value
        end

        # @rbs (json_value value, String path) -> bool
        def boolean(value, path)
          if [true, false].include?(value)
            result = value #: bool
            return result
          end

          invalid(path, "must be a boolean")
        end

        # @rbs (json_value value, String path, json_value expected) -> void
        def literal(value, path, expected)
          invalid(path, "must be #{expected.inspect}") unless value == expected
        end

        # @rbs (json_value value, String path, Array[String] values) -> String
        def enum(value, path, values)
          value = string(value, path)
          invalid(path, "must be one of #{values.join(', ')}") unless values.include?(value)
          value
        end

        # @rbs (json_value value, String path, ?nullable: bool) -> void
        def location(value, path, nullable: true)
          return if nullable && value.nil?

          value = record(value, path, %w[file line column])
          string(value["file"], "#{path}.file")
          positive_integer(value["line"], "#{path}.line")
          positive_integer(value["column"], "#{path}.column")
        end

        # @rbs (json_value value, String path) -> Integer
        def positive_integer(value, path)
          value = integer(value, path)
          invalid(path, "must be greater than or equal to 1") unless value.positive?
          value
        end

        # @rbs (json_value value, String path) -> String?
        def nullable_string(value, path)
          return nil if value.nil?

          string(value, path)
        end

        # @rbs (json_value value, String path) -> void
        def metadata(value, path)
          return if value.nil?

          value = string(value, path)
          invalid(path, "must not be empty") if value.strip.empty?
          invalid(path, "must be a single line") if value.match?(/[\r\n]/)
          invalid(path, "must not contain control characters") if value.match?(/[[:cntrl:]]/)
        end

        # @rbs (json_object value, String key, String path) -> json_value
        def field(value, key, path)
          value.fetch(key) { invalid(path, "is missing required field #{key.inspect}") }
        end

        # @rbs (String path, String key) -> String
        def child_path(path, key)
          key.match?(/\A[$A-Za-z_][$A-Za-z0-9_]*\z/) ? "#{path}.#{key}" : "#{path}[#{key.inspect}]"
        end

        # @rbs (String path, String message) -> bot
        def invalid(path, message)
          raise Ibex::Error, "#{POSITION}: #{path} #{message}"
        end
      end
    end
  end
end
