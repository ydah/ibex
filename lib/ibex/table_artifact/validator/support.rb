# frozen_string_literal: true

module Ibex
  module TableArtifact
    module ValidationSupport
      DIGEST = /\Asha256:[0-9a-f]{64}\z/

      private

      def record(value, path, keys)
        invalid(path, "must be an object") unless value.is_a?(Hash)
        invalid(path, "must use string keys") unless value.keys.all?(String)

        missing = keys - value.keys
        extra = value.keys - keys
        invalid(path, "is missing #{missing.join(', ')}") unless missing.empty?
        invalid(path, "contains unknown fields #{extra.join(', ')}") unless extra.empty?
        value
      end

      def array(value, path)
        invalid(path, "must be an array") unless value.is_a?(Array)
        value
      end

      def string(value, path, allow_empty: false)
        invalid(path, "must be a string") unless value.is_a?(String)
        invalid(path, "must not be empty") if !allow_empty && value.empty?
        value
      end

      def integer(value, path, minimum: nil)
        invalid(path, "must be an integer") unless value.is_a?(Integer)
        invalid(path, "must be at least #{minimum}") if minimum && value < minimum
        value
      end

      def boolean(value, path)
        invalid(path, "must be true or false") unless [true, false].include?(value)
        value
      end

      def enum(value, path, values)
        invalid(path, "must be one of #{values.join(', ')}") unless values.include?(value)
        value
      end

      def digest(value, path)
        invalid(path, "must be a sha256 digest") unless value.is_a?(String) && DIGEST.match?(value)
        value
      end

      def nullable_string(value, path)
        string(value, path, allow_empty: true) unless value.nil?
        value
      end

      def nullable_integer(value, path, minimum: nil)
        integer(value, path, minimum: minimum) unless value.nil?
        value
      end

      def sorted_unique!(values, path)
        invalid(path, "must be sorted and unique") unless values == values.sort.uniq
      end

      def invalid(path, message)
        raise ValidationError, "#{path} #{message}"
      end
    end
  end
end
