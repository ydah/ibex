# frozen_string_literal: true

module Ibex
  module Frontend
    class TokenAdapter
      # Tracks ordinary EBNF groups separately from separated-list calls.
      class DelimiterTracker
        attr_reader :group_opening, :open_kind

        def initialize
          @stack = []
        end

        def empty?
          @stack.empty?
        end

        def observe(token, external, previous_external)
          if external == "("
            separated = %i[SEPARATED_LIST SEPARATED_NONEMPTY_LIST].include?(previous_external)
            @stack << [separated ? :separated : :group, token]
          elsif external == ")"
            @stack.pop
          end
          @open_kind = @stack.last&.first
          @group_opening = @stack.reverse.find { |kind, _opening| kind == :group }&.last
        end
      end
    end
  end
end
