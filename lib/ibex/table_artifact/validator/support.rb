# frozen_string_literal: true

module Ibex
  module TableArtifact
    module ValidationSupport
      # @rbs!
      #   type json_value = String | Integer | Float | bool | nil | Array[json_value] | Hash[String, json_value]

      DIGEST = /\Asha256:[0-9a-f]{64}\z/ #: Regexp

      private

      # @rbs (json_value value, String path, Array[String] keys) -> Hash[String, json_value]
      def record(value, path, keys)
        invalid(path, "must be an object") unless value.is_a?(Hash)
        invalid(path, "must use string keys") unless value.keys.all?(String)

        missing = keys - value.keys
        extra = value.keys - keys
        invalid(path, "is missing #{missing.join(', ')}") unless missing.empty?
        invalid(path, "contains unknown fields #{extra.join(', ')}") unless extra.empty?
        value #: Hash[String, json_value]
      end

      # @rbs (json_value value, String path) -> Array[json_value]
      def array(value, path)
        invalid(path, "must be an array") unless value.is_a?(Array)
        value #: Array[json_value]
      end

      # @rbs (json_value value, String path, ?allow_empty: bool) -> String
      def string(value, path, allow_empty: false)
        invalid(path, "must be a string") unless value.is_a?(String)
        invalid(path, "must not be empty") if !allow_empty && value.empty?
        value #: String
      end

      # @rbs (json_value value, String path, ?minimum: Integer?) -> Integer
      def integer(value, path, minimum: nil)
        invalid(path, "must be an integer") unless value.is_a?(Integer)
        invalid(path, "must be at least #{minimum}") if minimum && value < minimum
        value #: Integer
      end

      # @rbs (json_value value, String path) -> bool
      def boolean(value, path)
        invalid(path, "must be true or false") unless [true, false].include?(value)
        value #: bool
      end

      # @rbs [T] (T value, String path, Array[T] values) -> T
      def enum(value, path, values)
        invalid(path, "must be one of #{values.join(', ')}") unless values.include?(value)
        value
      end

      # @rbs (json_value value, String path) -> String
      def digest(value, path)
        invalid(path, "must be a sha256 digest") unless value.is_a?(String) && DIGEST.match?(value)
        value
      end

      # @rbs (json_value value, String path) -> String?
      def nullable_string(value, path)
        string(value, path, allow_empty: true) unless value.nil?
        value #: String?
      end

      # @rbs (json_value value, String path, ?minimum: Integer?) -> Integer?
      def nullable_integer(value, path, minimum: nil)
        integer(value, path, minimum: minimum) unless value.nil?
        value #: Integer?
      end

      # @rbs (Array[json_value] values, String path) -> void
      def sorted_unique!(values, path)
        invalid(path, "must be sorted and unique") unless values == values.sort.uniq
      end

      # @rbs (String path, String message) -> bot
      def invalid(path, message)
        raise ValidationError, "#{path} #{message}"
      end
    end
  end
end
