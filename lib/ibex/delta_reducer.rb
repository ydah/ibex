# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  # Deterministic, trial-bounded delta debugging over an ordered sequence.
  class DeltaReducer
    # Immutable outcome of a bounded reduction.
    class Result
      attr_reader :items #: Array[untyped]
      attr_reader :trials #: Integer
      attr_reader :complete #: bool
      attr_reader :original_size #: Integer

      # @rbs (items: Array[untyped], trials: Integer, complete: bool, original_size: Integer) -> void
      def initialize(items:, trials:, complete:, original_size:)
        @items = items.freeze
        @trials = trials
        @complete = complete
        @original_size = original_size
        freeze
      end
    end

    # @rbs (?max_trials: Integer) -> void
    def initialize(max_trials: 1_000)
      raise ArgumentError, "max_trials must be positive" unless max_trials.positive?

      @max_trials = max_trials
    end

    # `failure` must return true while the failure of interest is preserved.
    # @rbs [T] (Array[T] items) { (Array[T]) -> bool } -> Result
    def minimize(items, &failure)
      raise ArgumentError, "a failure predicate is required" unless failure

      current = items.dup
      original_size = current.length
      trials = 0
      trials = checked_trial!(trials)
      unless failure.call(current.freeze)
        raise Ibex::Error, "(reduce):1:1: original input does not reproduce the failure"
      end

      granularity = 2
      while current.length >= 1
        chunks = partitions(current.length, granularity)
        reduced = false
        chunks.each do |range|
          return result(current, trials, false, original_size) if trials >= @max_trials

          candidate = current.dup
          candidate.slice!(range)
          trials = checked_trial!(trials)
          next unless failure.call(candidate.freeze)

          current = candidate
          granularity = [granularity - 1, 2].max
          reduced = true
          break
        end
        next if reduced
        break if granularity >= current.length

        granularity = [granularity * 2, current.length].min
      end

      result(current, trials, true, original_size)
    end

    private

    # @rbs (Integer length, Integer count) -> Array[Range[Integer]]
    def partitions(length, count)
      width = (length.to_f / count).ceil
      ranges = [] #: Array[Range[Integer]]
      count.times do |index|
        start = index * width
        break if start >= length

        ranges << (start...[start + width, length].min)
      end
      ranges
    end

    # @rbs (Integer trials) -> Integer
    def checked_trial!(trials)
      raise Ibex::Error, "(reduce):1:1: trial limit of #{@max_trials} is exhausted" if trials >= @max_trials

      trials + 1
    end

    # @rbs [T] (Array[T] items, Integer trials, bool complete, Integer original_size) -> Result
    def result(items, trials, complete, original_size)
      Result.new(
        items: items.dup.freeze, trials: trials, complete: complete, original_size: original_size
      ).freeze
    end
  end
end
