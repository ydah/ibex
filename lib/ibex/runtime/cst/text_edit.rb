# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # One byte-oriented source replacement.
      class TextEdit
        attr_reader :start #: Integer
        attr_reader :delete_length #: Integer
        attr_reader :insert_text #: String

        # @rbs (start: Integer, delete_length: Integer, insert_text: String) -> void
        def initialize(start:, delete_length:, insert_text:)
          raise ArgumentError, "start must be non-negative" if start.negative?
          raise ArgumentError, "delete_length must be non-negative" if delete_length.negative?

          @start = start
          @delete_length = delete_length
          @insert_text = insert_text.b.freeze
          freeze
        end

        # @rbs () -> Range[Integer]
        def range = @start...(@start + @delete_length)
      end
    end
  end
end
