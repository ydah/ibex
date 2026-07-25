# frozen_string_literal: true

module Ibex
  module Frontend
    class TokenAdapter
      # Tracks ordinary EBNF groups separately from separated-list calls.
      class DelimiterTracker
        attr_reader :group_opening #: Token?
        attr_reader :open_kind #: delimiter_kind?

        # @rbs @stack: Array[[delimiter_kind, Token]]

        # @rbs () -> void
        def initialize
          @stack = [] #: Array[[delimiter_kind, Token]]
        end

        # @rbs () -> bool
        def empty?
          @stack.empty?
        end

        # @rbs (Token token, external_token external, external_token? previous_external) -> void
        def observe(token, external, previous_external)
          if external == "("
            kind = if %i[SEPARATED_LIST SEPARATED_NONEMPTY_LIST].include?(previous_external)
                     :separated
                   elsif %i[LHS PARAMETERIZED_REFERENCE].include?(previous_external)
                     :parameter
                   else
                     :group
                   end #: delimiter_kind
            @stack << [kind, token] #: [delimiter_kind, Token]
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
