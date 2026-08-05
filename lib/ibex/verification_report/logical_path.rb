# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module VerificationReport
    # Closed logical identities used by version 1 verification reports.
    module LogicalPath
      MAX_INPUT_FILES = 10_000 #: Integer
      BASENAME = %r{\A(?!\.{1,2}\z)[^/\\\x00-\x1f\x7f]+\z} #: Regexp
      INPUT = %r{\Ainput/(?<index>[0-9]{4})/(?<basename>[^/\\\x00-\x1f\x7f]+)\z} #: Regexp
      TABLE = %r{\Atable/(?<basename>[^/\\\x00-\x1f\x7f]+)\z} #: Regexp

      module_function

      # @rbs (String path, Integer index) -> String
      def input(path, index)
        unless index.is_a?(Integer) && index.between?(0, MAX_INPUT_FILES - 1)
          raise ArgumentError, "verification reports support at most #{MAX_INPUT_FILES} input files"
        end

        "input/#{format('%04d', index)}/#{basename(path)}"
      end

      # @rbs (String path) -> String
      def table(path)
        "table/#{basename(path)}"
      end

      # @rbs (untyped value, Integer index) -> bool
      def canonical_input?(value, index)
        return false unless value.is_a?(String)

        match = INPUT.match(value)
        return false unless match

        basename = match[:basename]
        !!(basename && match[:index] == format("%04d", index) && usable_basename?(basename))
      end

      # @rbs (untyped value) -> bool
      def canonical_table?(value)
        return false unless value.is_a?(String)

        match = TABLE.match(value)
        return false unless match

        basename = match[:basename]
        !!(basename && usable_basename?(basename))
      end

      # @rbs (String path) -> String
      def basename(path)
        value = File.basename(path)
        return value if usable_basename?(value)

        raise ArgumentError, "artifact path has no usable logical basename"
      end
      private_class_method :basename

      # @rbs (String value) -> bool
      def usable_basename?(value)
        value.match?(BASENAME)
      end
      private_class_method :usable_basename?
    end
  end
end
