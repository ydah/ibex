# frozen_string_literal: true

module Ibex
  module IR
    module Validator
      # Shared JSON-shape checks for the two version-1 IR documents.
      class Base
        POSITION = "(ir):1:1"

        private

        # @rbs (untyped value, String path, Array[String] required, ?Array[String] optional) -> Hash[String, untyped]
        def record(value, path, required, optional = [])
          object(value, path)
          missing = required.reject { |key| value.key?(key) }
          invalid(path, "is missing required field #{missing.first.inspect}") unless missing.empty?
          unknown = value.keys - required - optional
          invalid(path, "has unsupported field #{unknown.first.inspect}") unless unknown.empty?
          value
        end

        # @rbs (untyped value, String path) -> Hash[String, untyped]
        def object(value, path)
          invalid(path, "must be an object") unless value.is_a?(Hash)
          value
        end

        # @rbs (untyped value, String path) -> Array[untyped]
        def array(value, path)
          invalid(path, "must be an array") unless value.is_a?(Array)
          value
        end

        # @rbs (untyped value, String path) -> String
        def string(value, path)
          invalid(path, "must be a string") unless value.is_a?(String)
          value
        end

        # @rbs (untyped value, String path) -> String
        def nonempty_string(value, path)
          string(value, path)
          invalid(path, "must not be empty") if value.empty?
          value
        end

        # @rbs (untyped value, String path) -> Integer
        def integer(value, path)
          invalid(path, "must be an integer") unless value.is_a?(Integer)
          value
        end

        # @rbs (untyped value, String path) -> Integer
        def nonnegative_integer(value, path)
          integer(value, path)
          invalid(path, "must be greater than or equal to 0") if value.negative?
          value
        end

        # @rbs (untyped value, String path) -> bool
        def boolean(value, path)
          invalid(path, "must be a boolean") unless [true, false].include?(value)
          value
        end

        # @rbs (untyped value, String path, untyped expected) -> void
        def literal(value, path, expected)
          invalid(path, "must be #{expected.inspect}") unless value == expected
        end

        # @rbs (untyped value, String path, Array[String] values) -> String
        def enum(value, path, values)
          string(value, path)
          invalid(path, "must be one of #{values.join(', ')}") unless values.include?(value)
          value
        end

        # @rbs (untyped value, String path, ?nullable: bool) -> void
        def location(value, path, nullable: true)
          return if nullable && value.nil?

          record(value, path, %w[file line column])
          string(value["file"], "#{path}.file")
          positive_integer(value["line"], "#{path}.line")
          positive_integer(value["column"], "#{path}.column")
        end

        # @rbs (untyped value, String path) -> Integer
        def positive_integer(value, path)
          integer(value, path)
          invalid(path, "must be greater than or equal to 1") unless value.positive?
          value
        end

        # @rbs (untyped value, String path) -> String?
        def nullable_string(value, path)
          return nil if value.nil?

          string(value, path)
        end

        # @rbs (untyped value, String path) -> void
        def metadata(value, path)
          return if value.nil?

          string(value, path)
          invalid(path, "must not be empty") if value.strip.empty?
          invalid(path, "must be a single line") if value.match?(/[\r\n]/)
          invalid(path, "must not contain control characters") if value.match?(/[[:cntrl:]]/)
        end

        # @rbs (Hash[String, untyped] value, String key, String path) -> untyped
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
