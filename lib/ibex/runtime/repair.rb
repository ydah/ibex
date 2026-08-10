# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # Explicit bounded cost and search policy for automatic token repair.
    class RepairPolicy
      attr_reader :insert_cost #: Integer
      attr_reader :delete_cost #: Integer
      attr_reader :replace_cost #: Integer
      attr_reader :max_cost #: Integer
      attr_reader :max_configurations #: Integer
      attr_reader :max_lookahead #: Integer
      attr_reader :success_shifts #: Integer
      attr_reader :max_stack #: Integer

      # @rbs (?insert_cost: Integer, ?delete_cost: Integer, ?replace_cost: Integer, ?max_cost: Integer,
      #   ?max_configurations: Integer, ?max_lookahead: Integer, ?success_shifts: Integer,
      #   ?max_stack: Integer) -> void
      def initialize(insert_cost: 1, delete_cost: 1, replace_cost: 2, max_cost: 3, max_configurations: 5_000,
                     max_lookahead: 8, success_shifts: 3, max_stack: 256)
        values = {
          insert_cost: insert_cost,
          delete_cost: delete_cost,
          replace_cost: replace_cost,
          max_cost: max_cost,
          max_configurations: max_configurations,
          max_lookahead: max_lookahead,
          success_shifts: success_shifts,
          max_stack: max_stack
        }
        invalid = values.find { |_name, value| !value.is_a?(Integer) || !value.positive? }
        raise ArgumentError, "#{invalid.first} must be a positive integer" if invalid
        raise ArgumentError, "success_shifts must not exceed max_lookahead" if success_shifts > max_lookahead

        values.each { |name, value| instance_variable_set(:"@#{name}", value) }
        freeze
      end
    end

    # One immutable insertion, deletion, or replacement.
    class RepairEdit
      # @rbs! type document_value = Symbol | Integer | String

      KINDS = %i[insert delete replace].freeze #: Array[Symbol]

      attr_reader :kind #: Symbol
      attr_reader :position #: Integer
      attr_reader :token_id #: Integer
      attr_reader :token_name #: String
      attr_reader :cost #: Integer

      # @rbs (kind: Symbol, position: Integer, token_id: Integer, token_name: String, cost: Integer) -> void
      def initialize(kind:, position:, token_id:, token_name:, cost:)
        raise ArgumentError, "unknown repair edit #{kind.inspect}" unless KINDS.include?(kind)
        raise ArgumentError, "repair edit position must be nonnegative" if position.negative?
        raise ArgumentError, "repair edit cost must be positive" unless cost.positive?

        @kind = kind
        @position = position
        @token_id = token_id
        @token_name = token_name.dup.freeze
        @cost = cost
        freeze
      end

      # @rbs () -> Hash[Symbol, document_value]
      def to_h
        { kind: @kind, position: @position, token_id: @token_id, token_name: @token_name, cost: @cost }.freeze
      end
    end

    # Deterministically selected repair.
    class RepairPlan
      attr_reader :edits #: Array[RepairEdit]
      attr_reader :cost #: Integer
      attr_reader :configurations #: Integer

      # @rbs (edits: Array[RepairEdit], configurations: Integer) -> void
      def initialize(edits:, configurations:)
        raise ArgumentError, "repair plan must contain an edit" if edits.empty?

        @edits = edits.dup.freeze
        @cost = @edits.sum(&:cost)
        @configurations = configurations
        freeze
      end

      # @rbs () -> Hash[Symbol, Integer | Array[Hash[Symbol, RepairEdit::document_value]]]
      def to_h
        { cost: @cost, configurations: @configurations, edits: @edits.map(&:to_h).freeze }.freeze
      end
    end

    # Closed internal outcome for callers that must distinguish bounded search
    # exhaustion from a complete search with no repair.
    class RepairSearchResult
      STATUSES = %i[selected need_input exhausted not_found].freeze #: Array[Symbol]

      attr_reader :status #: Symbol
      attr_reader :plan #: RepairPlan?
      attr_reader :configurations #: Integer

      # @rbs (status: Symbol, plan: RepairPlan?, configurations: Integer) -> void
      def initialize(status:, plan:, configurations:)
        raise ArgumentError, "unknown repair search status #{status.inspect}" unless STATUSES.include?(status)
        unless configurations.is_a?(Integer) && configurations >= 0
          raise ArgumentError, "repair search configurations must be nonnegative"
        end
        unless (status == :selected) == plan.is_a?(RepairPlan)
          raise ArgumentError, "selected repair search status and plan must agree"
        end

        @status = status
        @plan = plan
        @configurations = configurations
        freeze
      end

      # @rbs () -> bool
      def selected? = @status == :selected
    end

    # Internal normalized input record retained while repair looks ahead.
    class RepairInput
      attr_reader :token_id #: Integer
      attr_reader :token_name #: String
      attr_reader :value #: Object?
      attr_reader :location #: Object?

      # @rbs (token_id: Integer, token_name: String, value: Object?, location: Object?) -> void
      def initialize(token_id:, token_name:, value:, location:)
        @token_id = token_id
        @token_name = token_name.dup.freeze
        @value = value
        @location = location
        freeze
      end

      # @rbs () -> bool
      def eof? = @token_id.zero?
    end

    # Internal result of simulating reductions followed by one table action.
    class RepairAdvance
      attr_reader :status #: :shift | :accept
      attr_reader :stack #: Array[Integer]

      # @rbs (status: :shift | :accept, stack: Array[Integer]) -> void
      def initialize(status:, stack:)
        @status = status
        @stack = stack
        freeze
      end
    end
  end
end
