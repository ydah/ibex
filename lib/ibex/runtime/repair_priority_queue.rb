# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # Minimal binary heap ordered by an immutable Array priority.
    class RepairPriorityQueue
      # @rbs!
      #   type priority = [
      #     Integer, Integer, Array[[Integer, Integer, Integer]], Integer,
      #     Integer, Array[Integer]
      #   ]
      # @rbs @entries: Array[[priority, Object?]]

      # @rbs () -> void
      def initialize
        @entries = []
      end

      # @rbs () -> bool
      def empty? = @entries.empty?

      # @rbs (priority priority, Object? value) -> void
      def push(priority, value)
        entry = [priority, value] #: [priority, Object?]
        @entries << entry
        index = @entries.length - 1
        while index.positive?
          parent = (index - 1) / 2
          break if compare(@entries[parent], entry) <= 0

          @entries[index] = @entries[parent]
          index = parent
        end
        @entries[index] = entry
      end

      # @rbs () -> [priority, Object?]?
      def pop
        first = @entries.first
        tail = @entries.pop
        return first if @entries.empty? || !first || !tail

        index = 0
        while (child = (index * 2) + 1) < @entries.length
          right = child + 1
          child = right if right < @entries.length && compare(@entries[right], @entries[child]).negative?
          break if compare(tail, @entries[child]) <= 0

          @entries[index] = @entries[child]
          index = child
        end
        @entries[index] = tail
        first
      end

      private

      # @rbs ([priority, Object?] left, [priority, Object?] right) -> Integer
      def compare(left, right)
        left_priority = left.fetch(0) #: priority
        right_priority = right.fetch(0) #: priority
        (left_priority <=> right_priority) || 0
      end
    end
  end
end
