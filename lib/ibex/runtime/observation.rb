# frozen_string_literal: true
# rbs_inline: enabled

require_relative "event" unless defined?(Ibex::Runtime::Event)

module Ibex
  module Runtime
    # Registration and ordered synchronous dispatch for parser observers.
    module Observation
      # Opaque identity returned by Parser#observe.
      class Subscription
        class << self
          private

          # @rbs () -> Subscription
          def new
            super.freeze
          end

          # @rbs () -> Subscription
          # rubocop:disable Lint/UselessMethodDefinition -- explicit override keeps runtime and generated RBS private.
          def allocate
            super
          end
          # rubocop:enable Lint/UselessMethodDefinition
        end
      end

      # @rbs () { (Event) -> void } -> Subscription
      def observe(&observer)
        raise ArgumentError, "observe requires a block" unless observer

        @runtime_observation_mutex.synchronize do
          ensure_observation_thread!
          subscription = Subscription.__send__(:new)
          @runtime_observers ||= {} #: Hash[Subscription, Proc]
          @runtime_observers[subscription] = observer
          subscription
        end
      end

      # @rbs (Subscription subscription) -> bool
      def unobserve(subscription)
        @runtime_observation_mutex.synchronize do
          ensure_observation_thread!
          observers = @runtime_observers
          next false unless observers

          removed = !observers.delete(subscription).nil?
          @runtime_observers = nil if observers.empty?
          removed
        end
      end

      private

      # @rbs (Symbol type, Hash[untyped, untyped] data, ?observers: Array[Proc]?) -> void
      def emit_runtime_event(type, data, observers: runtime_observer_snapshot)
        return unless observers

        @runtime_event_sequence += 1
        event = Event.new(type: type, sequence: @runtime_event_sequence, data: data)
        observers.each { |observer| observer.call(event) }
      end

      # @rbs () -> Array[Proc]?
      def runtime_observer_snapshot
        @runtime_observers&.values
      end

      # @rbs () -> void
      def ensure_observation_thread!
        return if @driver_status == :idle || @runtime_driver_thread == Thread.current

        raise ThreadError, "parser observers cannot be changed from another thread while a driver is active"
      end
    end
  end
end
