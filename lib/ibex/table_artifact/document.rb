# frozen_string_literal: true

module Ibex
  module TableArtifact
    # An immutable, validated table artifact document.
    class Document
      attr_reader :data

      def initialize(data)
        Validator.validate!(data)
        @data = Serializer.deep_freeze(data)
      end

      def dump
        Serializer.dump(@data)
      end

      def payload
        @data.fetch("payload")
      end

      def identity
        @data.fetch("identity")
      end

      def cost
        @data.fetch("cost")
      end
    end
  end
end
