# frozen_string_literal: true
# rbs_inline: enabled

require_relative "text_edit" unless defined?(Ibex::Runtime::CST::TextEdit)

module Ibex
  module Runtime
    module CST
      # Computes byte edits while skipping physically shared Green subtrees.
      module Diff
        # @rbs (SyntaxNode old_root, SyntaxNode new_root) -> Array[TextEdit]
        def text_edits(old_root, new_root)
          edits = [] #: Array[TextEdit]
          compare(old_root.green, new_root.green, 0, edits)
          edits.freeze
        end
        module_function :text_edits

        # @rbs (GreenNode | GreenToken old_green, GreenNode | GreenToken new_green,
        #   Integer offset, Array[TextEdit] edits) -> void
        def compare(old_green, new_green, offset, edits)
          return if old_green.equal?(new_green)

          if old_green.is_a?(GreenNode) && new_green.is_a?(GreenNode) &&
             compatible_nodes?(old_green, new_green)
            child_offset = offset
            old_green.children.each_with_index do |old_child, index|
              new_child = new_green.children.fetch(index)
              compare(old_child, new_child, child_offset, edits)
              child_offset += old_child.full_width
            end
            return
          end

          append_trimmed_edit(old_green.to_source, new_green.to_source, offset, edits)
        end
        module_function :compare

        # @rbs (GreenNode | GreenToken left, GreenNode | GreenToken right) -> bool
        def compatible_nodes?(left, right)
          left.is_a?(GreenNode) && right.is_a?(GreenNode) &&
            left.kind == right.kind && left.children.length == right.children.length
        end
        module_function :compatible_nodes?

        # @rbs (String old_text, String new_text, Integer offset, Array[TextEdit] edits) -> void
        def append_trimmed_edit(old_text, new_text, offset, edits)
          return if old_text == new_text

          prefix = common_prefix(old_text, new_text)
          suffix = common_suffix(old_text, new_text, prefix)
          deleted = old_text.bytesize - prefix - suffix
          inserted = new_text.byteslice(prefix, new_text.bytesize - prefix - suffix) || "".b
          edits << TextEdit.new(start: offset + prefix, delete_length: deleted, insert_text: inserted)
        end
        module_function :append_trimmed_edit

        # @rbs (String left, String right) -> Integer
        def common_prefix(left, right)
          limit = [left.bytesize, right.bytesize].min
          index = 0
          index += 1 while index < limit && left.getbyte(index) == right.getbyte(index)
          index
        end
        module_function :common_prefix

        # @rbs (String left, String right, Integer prefix) -> Integer
        def common_suffix(left, right, prefix)
          limit = [left.bytesize, right.bytesize].min - prefix
          index = 0
          index += 1 while index < limit && left.getbyte(-index - 1) == right.getbyte(-index - 1)
          index
        end
        module_function :common_suffix

        private_class_method :compare, :compatible_nodes?, :append_trimmed_edit, :common_prefix, :common_suffix
      end
    end
  end
end
