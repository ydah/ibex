# frozen_string_literal: true

require "json"
require "digest"
require_relative "validator/base"
require_relative "validator/grammar"
require_relative "validator/automaton"
require_relative "validator/lexer"

module Ibex
  module IR
    # Validates a serialized public IR document before constructing immutable IR objects.
    module Validator
      POSITION = "(ir):1:1"

      # @rbs (String source) -> (Grammar | Automaton | Lexer)
      def validate(source)
        data = JSON.parse(source)
        raise Ibex::Error, "#{POSITION}: $ must be an object" unless data.is_a?(Hash)

        type = data.fetch("ibex_ir") { raise Ibex::Error, "#{POSITION}: missing ibex_ir discriminator" }
        version = data["schema_version"]
        supported = type == "lexer" ? SUPPORTED_LEXER_SCHEMA_VERSIONS : SUPPORTED_SCHEMA_VERSIONS
        unless supported.include?(version)
          expected = supported.join(", ")
          raise Ibex::Error, "#{POSITION}: unsupported schema_version #{version.inspect}; expected the current format (#{expected})"
        end

        case type
        when "grammar" then GrammarDocument.new(data, version: version).validate
        when "automaton" then AutomatonDocument.new(data, version: version).validate
        when "lexer" then LexerDocument.new(data).validate
        else raise Ibex::Error, "#{POSITION}: unsupported IR type #{type.inspect}"
        end
        value = Serialize.load(source)
        validate_automaton_digest(value) if value.is_a?(Automaton)
        value
      rescue JSON::ParserError => e
        raise Ibex::Error, "#{POSITION}: invalid JSON: #{e.message}"
      rescue Ibex::Error
        raise
      rescue KeyError, NoMethodError, TypeError, ArgumentError => e
        raise Ibex::Error, "#{POSITION}: invalid IR structure: #{e.message}"
      end
      module_function :validate

      # @rbs (Automaton automaton) -> void
      def validate_automaton_digest(automaton)
        expected = "sha256:#{Digest::SHA256.hexdigest(Serialize.dump(automaton.grammar))}"
        return if automaton.grammar_digest == expected

        raise Ibex::Error,
              "#{POSITION}: $.grammar_digest does not match the embedded grammar; expected #{expected.inspect}"
      end
      module_function :validate_automaton_digest

      class << self
        private :validate_automaton_digest
      end
    end
  end
end
