# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Watch
    # Polls source fingerprints, debounces changes, and publishes stable builds.
    class Runner
      DEFAULT_INTERVAL = 0.25 #: Float
      DEFAULT_DEBOUNCE = 0.05 #: Float

      # rubocop:disable Layout/LineLength
      # @rbs (paths: Array[String], build: ^() -> untyped, publish: ^(untyped, SourceSnapshot, ^() -> bool) -> void, failure_paths: ^() -> Array[String], stderr: untyped, clock: ^() -> Float, sleeper: ^(Float) -> void, iteration_hook: ^(Symbol, Integer, Array[String]) -> (Integer | Symbol | nil), ?interval: Float, ?debounce: Float) -> void
      def initialize(paths:, build:, publish:, failure_paths:, stderr:, clock:, sleeper:, iteration_hook:,
                     interval: DEFAULT_INTERVAL, debounce: DEFAULT_DEBOUNCE)
        @fixed_paths = normalize_paths(paths)
        @successful_paths = [] #: Array[String]
        @paths = @fixed_paths
        @build = build
        @publish = publish
        @failure_paths = failure_paths
        @stderr = stderr
        @clock = clock
        @sleeper = sleeper
        @iteration_hook = iteration_hook
        @interval = interval
        @debounce = debounce
        @signal_status = nil #: Integer?
        @requested_status = nil #: Integer?
        @last_failure_message = nil #: String?
        @last_failure_snapshot = nil #: SourceSnapshot?
        @iteration = 0
      end
      # rubocop:enable Layout/LineLength

      # @rbs () -> Integer
      def run
        with_signal_handlers do
          snapshot = SourceSnapshot.new(@paths)
          loop do
            status = stop_status(:before_build)
            return status if status

            snapshot, retry_build = build_once(snapshot)
            status = stop_status(:after_build)
            return status if status

            if retry_build
              snapshot = debounce(snapshot)
              status = @signal_status || @requested_status
              return status if status

              next
            end

            snapshot = wait_for_change(snapshot)
            status = @signal_status || @requested_status
            return status if status
          end
        end
      end

      private

      # @rbs (SourceSnapshot before) -> [SourceSnapshot, bool]
      def build_once(before)
        @iteration += 1
        result = @build.call
        @paths = normalize_paths(@fixed_paths + result.source_paths + result.attempted_paths)
        rendered = SourceSnapshot.new(@paths)
        return [rendered, true] unless rendered.unchanged_since?(before)
        return [rendered, false] if @signal_status

        @publish.call(result, rendered, -> { @signal_status.nil? })
        @last_failure_message = nil
        @last_failure_snapshot = nil
        @successful_paths = @paths - @fixed_paths
        published = SourceSnapshot.new(@paths)
        [published, published != rendered]
      rescue GenerationTransaction::SourceChanged
        [SourceSnapshot.new(@paths), true]
      rescue GenerationTransaction::Error => e
        raise if e.rollback_failed

        failed_build(before, e)
      rescue Ibex::Error, SystemCallError, SystemStackError => e
        failed_build(before, e)
      end

      # @rbs (SourceSnapshot snapshot) -> SourceSnapshot
      def wait_for_change(snapshot)
        loop do
          @sleeper.call(@interval)
          return snapshot if @signal_status

          status = stop_status(:poll)
          return snapshot if status

          changed = SourceSnapshot.new(@paths)
          next if changed == snapshot

          return debounce(changed)
        end
      end

      # @rbs (SourceSnapshot changed) -> SourceSnapshot
      def debounce(changed)
        loop do
          @clock.call
          @sleeper.call(@debounce)
          return changed if @signal_status

          settled = SourceSnapshot.new(@paths)
          return settled if settled == changed

          changed = settled
        end
      end

      # @rbs (Exception error) -> void
      def report_failure(error)
        @stderr.puts(error.message)
      end

      # @rbs (SourceSnapshot before, Exception error) -> [SourceSnapshot, bool]
      def failed_build(before, error)
        previous_paths = @paths
        @paths = normalize_paths(@fixed_paths + @successful_paths + @failure_paths.call)
        current = SourceSnapshot.new(@paths)
        retry_build = @paths != previous_paths || !current.unchanged_since?(before)
        report_failure_once(error, current)
        [current, retry_build]
      end

      # @rbs (Exception error, SourceSnapshot snapshot) -> void
      def report_failure_once(error, snapshot)
        duplicate = @last_failure_message == error.message && @last_failure_snapshot == snapshot
        report_failure(error) unless duplicate
        @last_failure_message = error.message
        @last_failure_snapshot = snapshot
      end

      # @rbs (Symbol event) -> Integer?
      def stop_status(event)
        return @signal_status if @signal_status

        result = @iteration_hook.call(event, @iteration, @paths.dup)
        @requested_status = result if result.is_a?(Integer)
        @requested_status = 0 if result == :stop
        return @requested_status if @requested_status

        nil
      end

      # @rbs (Array[String] paths) -> Array[String]
      def normalize_paths(paths)
        paths.map { |path| File.expand_path(path) }.uniq.sort
      end

      # @rbs () { () -> Integer } -> Integer
      def with_signal_handlers
        previous = {} #: Hash[String, untyped]
        if Thread.current == Thread.main
          previous["INT"] = Signal.trap("INT") { @signal_status = 130 }
          previous["TERM"] = Signal.trap("TERM") { @signal_status = 143 }
        end
        yield
      ensure
        previous&.each { |signal, handler| Signal.trap(signal, handler) }
      end
    end
  end
end
