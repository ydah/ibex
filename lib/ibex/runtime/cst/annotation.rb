# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # Opaque identity used to track a syntax occurrence across path-copying edits.
      class SyntaxAnnotation
        # @rbs () -> void
        def initialize
          freeze
        end
      end
    end
  end
end
