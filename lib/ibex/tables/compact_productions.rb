# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Tables
    # Production metadata with parallel primitive arrays for the direct parser
    # and a compatible Array-of-Hash surface for generic runtime consumers.
    class CompactProductions < Array #[Hash[Symbol, untyped]]
      VALUES_ACTION = 1 #: Integer
      BORROWED_VALUES_ACTION = 2 #: Integer
      LOCATION_ACTION = 4 #: Integer
      COMPOSITION_ACTION = 8 #: Integer
      VALID_FLAGS = VALUES_ACTION | BORROWED_VALUES_ACTION | LOCATION_ACTION | COMPOSITION_ACTION #: Integer
      CORE_FIELDS = %i[
        lhs length action values_action borrowed_values_action location_action composition_action
      ].freeze #: Array[Symbol]
      private_constant :VALID_FLAGS, :CORE_FIELDS

      attr_reader :lhs_ids #: Array[Integer]
      attr_reader :lengths #: Array[Integer]
      attr_reader :actions #: Array[Symbol?]
      attr_reader :flags #: Array[Integer]

      class << self
        # @rbs (Array[Hash[Symbol, untyped]] productions) -> CompactProductions
        def build(productions)
          lhs_ids = [] #: Array[Integer]
          lengths = [] #: Array[Integer]
          actions = [] #: Array[Symbol?]
          flags = [] #: Array[Integer]
          metadata = {} #: Hash[Integer, Hash[Symbol, untyped]]
          productions.each_with_index do |production, index|
            lhs_ids << production.fetch(:lhs)
            lengths << production.fetch(:length)
            actions << production[:action]
            flags << flags_for(production)
            extra = production.except(
              :lhs, :length, :action, :values_action, :borrowed_values_action, :location_action, :composition_action
            )
            metadata[index] = extra unless extra.empty?
          end
          new(lhs_ids: lhs_ids, lengths: lengths, actions: actions, flags: flags, metadata: metadata)
        end

        # @rbs (String lhs_ids, String lengths, String flags,
        #   ?metadata: Hash[Integer, Hash[Symbol, untyped]]) -> CompactProductions
        def packed(lhs_ids, lengths, flags, metadata: {})
          decoded_flags = PackedIntegers.decode_required(flags)
          actions = decoded_flags.each_index.map do |index|
            :"_ibex_action_#{index}" unless decoded_flags[index].zero?
          end
          new(
            lhs_ids: PackedIntegers.decode_required(lhs_ids),
            lengths: PackedIntegers.decode_required(lengths),
            actions: actions,
            flags: decoded_flags,
            metadata: metadata
          )
        end

        private

        # @rbs (Hash[Symbol, untyped] production) -> Integer
        def flags_for(production)
          value = 0
          value |= VALUES_ACTION if production[:values_action] == true
          value |= BORROWED_VALUES_ACTION if production[:borrowed_values_action] == true
          value |= LOCATION_ACTION if production[:location_action] == true
          value |= COMPOSITION_ACTION if production[:composition_action] == true
          value
        end
      end

      # @rbs (lhs_ids: Array[Integer], lengths: Array[Integer], actions: Array[Symbol?],
      #   flags: Array[Integer], ?metadata: Hash[Integer, Hash[Symbol, untyped]]) -> void
      def initialize(lhs_ids:, lengths:, actions:, flags:, metadata: {})
        size = lhs_ids.length
        unless lengths.length == size && actions.length == size && flags.length == size
          raise ArgumentError, "compact production arrays must have the same length"
        end

        @lhs_ids = lhs_ids.map { |value| nonnegative_integer!(value, "lhs") }.freeze
        @lengths = lengths.map { |value| nonnegative_integer!(value, "length") }.freeze
        @actions = actions.map { |value| action!(value) }.freeze
        @flags = flags.map { |value| flags!(value) }.freeze
        validate_markers!
        validate_metadata!(metadata, size)
        super(Array.new(size) { |index| decode(index, metadata[index]) })
        freeze
      end

      # @rbs () -> bool
      def direct_values?
        @direct_values
      end

      private

      # @rbs (untyped value, String name) -> Integer
      def nonnegative_integer!(value, name)
        return value if value.is_a?(Integer) && !value.negative?

        raise ArgumentError, "compact production #{name} must be a nonnegative Integer"
      end

      # @rbs (untyped value) -> Symbol?
      def action!(value)
        return value if value.nil? || value.is_a?(Symbol)

        raise ArgumentError, "compact production action must be a Symbol or nil"
      end

      # @rbs (untyped value) -> Integer
      def flags!(value)
        return value if value.is_a?(Integer) && !value.negative? && value.nobits?(~VALID_FLAGS)

        raise ArgumentError, "compact production flags are invalid"
      end

      # @rbs () -> void
      def validate_markers!
        @flags.each_with_index do |value, index|
          borrowed = value.anybits?(BORROWED_VALUES_ACTION)
          values = value.anybits?(VALUES_ACTION)
          raise ArgumentError, "borrowed production #{index} must be a values action" if borrowed && !values
        end
        @direct_values = @actions.each_index.all? do |index|
          @actions[index].nil? || @flags[index].anybits?(VALUES_ACTION)
        end
      end

      # @rbs (Hash[Integer, Hash[Symbol, untyped]] metadata, Integer size) -> void
      def validate_metadata!(metadata, size)
        metadata.each do |index, entry|
          unless index.is_a?(Integer) && index.between?(0, size - 1) && entry.is_a?(Hash)
            raise ArgumentError, "compact production metadata is invalid"
          end
          if entry.keys.any? { |key| CORE_FIELDS.include?(key) }
            raise ArgumentError, "compact production metadata cannot replace core fields"
          end
        end
      end

      # @rbs (Integer index, Hash[Symbol, untyped]? metadata) -> Hash[Symbol, untyped]
      def decode(index, metadata)
        entry = {} #: Hash[Symbol, untyped]
        entry[:lhs] = @lhs_ids[index]
        entry[:length] = @lengths[index]
        entry[:action] = @actions[index]
        value = @flags[index]
        entry[:values_action] = true if value.anybits?(VALUES_ACTION)
        entry[:borrowed_values_action] = true if value.anybits?(BORROWED_VALUES_ACTION)
        entry[:location_action] = true if value.anybits?(LOCATION_ACTION)
        entry[:composition_action] = true if value.anybits?(COMPOSITION_ACTION)
        entry.merge!(metadata) if metadata
        entry.freeze
      end
    end
  end
end
