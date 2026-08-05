# frozen_string_literal: true

module Ibex
  module TableArtifact
    # An immutable, validated table artifact document.
    class Document
      attr_reader :data #: Hash[String, untyped]

      # @rbs (Hash[String, untyped] data) -> void
      def initialize(data)
        Validator.validate!(data)
        @data = Serializer.deep_freeze(data)
      end

      # @rbs () -> String
      def dump
        Serializer.dump(@data)
      end

      # @rbs () -> Hash[String, untyped]
      def payload
        @data.fetch("payload")
      end

      # @rbs () -> Hash[String, String]
      def identity
        @data.fetch("identity")
      end

      # @rbs () -> Hash[String, untyped]
      def cost
        @data.fetch("cost")
      end
    end
  end
end
