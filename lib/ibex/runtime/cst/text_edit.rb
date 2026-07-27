# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # One byte-oriented source replacement.
      class TextEdit
        class << self
          # Sort and merge adjacent edits while rejecting intersecting source ranges.
          # All edits remain expressed against the unedited source.
          # @rbs (Array[TextEdit] edits) -> Array[TextEdit]
          def normalize(edits)
            raise ArgumentError, "edits must contain only TextEdit values" unless edits.all?(TextEdit)

            merge_adjacent(
              edits.each_with_index.sort_by do |edit, index|
                [edit.start, edit.delete_length.zero? ? 0 : 1, index]
              end.map(&:first)
            ).freeze
          end

          private

          # @rbs (Array[TextEdit] ordered) -> Array[TextEdit]
          def merge_adjacent(ordered)
            normalized = [] #: Array[TextEdit]
            ordered.each do |edit|
              previous = normalized.last
              unless previous
                normalized << edit
                next
              end

              merge_with_previous(normalized, previous, edit)
            end
            normalized
          end

          # @rbs (Array[TextEdit] normalized, TextEdit previous, TextEdit edit) -> void
          def merge_with_previous(normalized, previous, edit)
            previous_end = previous.start + previous.delete_length
            raise ArgumentError, "text edits overlap" if edit.start < previous_end

            if edit.start == previous_end
              normalized[-1] = TextEdit.new(
                start: previous.start,
                delete_length: previous.delete_length + edit.delete_length,
                insert_text: previous.insert_text + edit.insert_text
              )
            else
              normalized << edit
            end
          end
        end

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
