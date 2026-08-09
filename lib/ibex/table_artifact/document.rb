# frozen_string_literal: true

module Ibex
  module TableArtifact
    # An immutable, validated table artifact document.
    class Document
      # @rbs!
      #   type json_value = String | Integer | Float | bool | nil | Array[json_value] | Hash[String, json_value]

      attr_reader :data #: Hash[String, json_value]

      # @rbs (Hash[String, json_value] data) -> void
      def initialize(data)
        Validator.validate!(data)
        @data = Serializer.deep_freeze(data)
      end

      # @rbs () -> String
      def dump
        Serializer.dump(@data)
      end

      # @rbs () -> Hash[String, json_value]
      def payload
        @data.fetch("payload") #: Hash[String, json_value]
      end

      # @rbs () -> Hash[String, String]
      def identity
        @data.fetch("identity") #: Hash[String, String]
      end

      # @rbs () -> Hash[String, json_value]
      def cost
        @data.fetch("cost") #: Hash[String, json_value]
      end
    end
  end
end
