# frozen_string_literal: true

require "digest"
require "json"
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
    ARTIFACT_TYPE = "ibex.parser-table"
    SCHEMA_VERSION = 1
    DEFAULT_MAX_BYTES = 16 * 1024 * 1024

    class ValidationError < Ibex::Error; end

    module_function

    def build(automaton, representation: :compact, cst_trivia: nil, omit_action_call: nil)
      Builder.new(
        automaton,
        representation: representation,
        cst_trivia: cst_trivia,
        omit_action_call: omit_action_call
      ).build
    end

    def load(source, max_bytes: DEFAULT_MAX_BYTES)
      bytes = read_bounded(source, max_bytes)
      unless bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding?
        raise ValidationError, "table artifact must be UTF-8 JSON"
      end

      Document.new(JSON.parse(bytes))
    rescue JSON::ParserError => e
      raise ValidationError, "invalid table artifact JSON: #{e.message}"
    end

    def read_bounded(source, max_bytes)
      raise ArgumentError, "max_bytes must be positive" unless max_bytes.positive?

      bytes = source.respond_to?(:read) ? source.read(max_bytes + 1) : String(source)
      bytes ||= ""
      raise ValidationError, "table artifact exceeds #{max_bytes} bytes" if bytes.bytesize > max_bytes

      bytes
    end
    private_class_method :read_bounded
  end
end
