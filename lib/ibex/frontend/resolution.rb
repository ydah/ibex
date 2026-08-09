# frozen_string_literal: true

module Ibex
  module Frontend
    # Immutable result of resolving one root grammar and its fragment closure.
    class Resolution
      EMPTY_CHAIN = Array.new(0).freeze #: Array[IR::source_provenance]
      private_constant :EMPTY_CHAIN

      attr_reader :root #: AST::Root
      attr_reader :root_path #: String
      attr_reader :root_directory #: String
      attr_reader :files #: Array[String]

      # @rbs (root: AST::Root, root_path: String, root_directory: String, files: Array[String],
      #   include_chains: Hash[AST::Rule, Array[IR::source_provenance]]) -> void
      def initialize(root:, root_path:, root_directory:, files:, include_chains:)
        @root = deep_freeze_ast(root)
        @root_path = root_path.dup.freeze
        @root_directory = root_directory.dup.freeze
        @files = files.map { |file| file.dup.freeze }.freeze
        chains = {} #: Hash[AST::Rule, Array[IR::source_provenance]]
        @include_chains = chains.compare_by_identity
        include_chains.each do |rule, chain|
          frozen_chain = chain.map { |entry| copy_provenance(entry) }.freeze
          @include_chains[rule] = frozen_chain
        end
        @include_chains.freeze
        freeze
      end

      # @rbs (AST::Rule rule) -> Array[IR::source_provenance]
      def include_chain_for(rule)
        @include_chains.fetch(rule, EMPTY_CHAIN)
      end

      private

      # AST payloads are recursively heterogeneous and are only traversed to freeze them.
      # @rbs (Object? value) -> Object?
      def deep_freeze_ast(value)
        case value
        when Struct
          value.each_pair { |_name, child| deep_freeze_ast(child) }
        when Array
          value.each { |child| deep_freeze_ast(child) }
        when Hash
          value.each do |key, child|
            deep_freeze_ast(key)
            deep_freeze_ast(child)
          end
        end
        value.freeze
      end

      # @rbs (IR::source_provenance entry) -> IR::source_provenance
      def copy_provenance(entry)
        span = entry[:byte_span]
        frozen_span = span && { start: span[:start], end: span[:end] } #: IR::byte_span?
        frozen_span&.freeze
        provenance = {
          file: entry[:file]&.dup&.freeze,
          root: entry[:root]&.dup&.freeze,
          byte_span: frozen_span
        } #: IR::source_provenance
        provenance.freeze
      end
    end
  end
end
