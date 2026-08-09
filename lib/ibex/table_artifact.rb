# frozen_string_literal: true

require "digest"
require "json"
require "set"
require_relative "error"
require_relative "ir"
require_relative "tables"
require_relative "runtime/table_format"
require_relative "codegen/cst_metadata"
require_relative "table_artifact/serializer"
require_relative "table_artifact/validator"
require_relative "table_artifact/document"
require_relative "table_artifact/cst_projection"
require_relative "table_artifact/builder"
require_relative "table_artifact/executor"

module Ibex
  # Experimental data-only authority for executable parser tables.
  module TableArtifact
    # @rbs!
    #   interface _Reader
    #     def read: (Integer length) -> String?
    #   end

    ARTIFACT_TYPE = "ibex.parser-table" #: String
    SCHEMA_VERSION = 1 #: Integer
    DEFAULT_MAX_BYTES = 16 * 1024 * 1024 #: Integer

    class ValidationError < Ibex::Error; end

    class << self
      # @rbs (IR::Automaton automaton, ?representation: Symbol | String, ?cst_trivia: Symbol | String?,
      #   ?omit_action_call: bool?) -> Document
      def build(automaton, representation: :compact, cst_trivia: nil, omit_action_call: nil)
        Builder.new(
          automaton,
          representation: representation,
          cst_trivia: cst_trivia,
          omit_action_call: omit_action_call
        ).build
      end

      # @rbs (String | _Reader source, ?max_bytes: Integer) -> Document
      def load(source, max_bytes: DEFAULT_MAX_BYTES)
        bytes = read_bounded(source, max_bytes)
        unless bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding?
          raise ValidationError, "table artifact must be UTF-8 JSON"
        end

        Document.new(JSON.parse(bytes))
      rescue JSON::ParserError => e
        raise ValidationError, "invalid table artifact JSON: #{e.message}"
      end

      private

      # @rbs (String | _Reader source, Integer max_bytes) -> String
      def read_bounded(source, max_bytes)
        raise ArgumentError, "max_bytes must be positive" unless max_bytes.is_a?(Integer) && max_bytes.positive?

        bytes = if source.respond_to?(:read)
                  read_from(source, max_bytes)
                else
                  String(source)
                end
        raise ValidationError, "table artifact exceeds #{max_bytes} bytes" if bytes.bytesize > max_bytes

        bytes
      end

      # @rbs (_Reader source, Integer max_bytes) -> String
      def read_from(source, max_bytes)
        bytes = +"".b
        loop do
          chunk = source.read((max_bytes + 1) - bytes.bytesize)
          break if chunk.nil?
          raise ValidationError, "table artifact reader must return strings" unless chunk.is_a?(String)
          break if chunk.empty?

          bytes << chunk
          break if bytes.bytesize > max_bytes
        end
        bytes
      end
    end
  end
end
