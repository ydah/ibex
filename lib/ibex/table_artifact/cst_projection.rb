# frozen_string_literal: true

module Ibex
  module TableArtifact
    # Converts code-generation CST metadata into closed JSON records.
    module CSTProjection
      private

      # @rbs () -> Hash[String, untyped]?
      def cst
        return unless @grammar.options[:cst]

        normalize_cst(Codegen::CSTMetadata.new(@grammar, trivia_policy: @cst_trivia).build)
      end

      # @rbs (untyped metadata) -> Hash[String, untyped]
      def normalize_cst(metadata)
        kinds = metadata.fetch(:kinds)
        {
          "version" => metadata.fetch(:version),
          "trivia_policy" => metadata.fetch(:trivia_policy).to_s,
          "kinds" => normalize_cst_kinds(kinds),
          "slots" => metadata.fetch(:slots).sort.map { |production_id, slot| normalize_cst_slot(production_id, slot) }
        }
      end

      # @rbs (untyped kinds) -> Hash[String, untyped]
      def normalize_cst_kinds(kinds)
        {
          "names" => kinds.fetch(:names),
          "terminal_range" => kinds.fetch(:terminal_range),
          "nonterminal_range" => kinds.fetch(:nonterminal_range),
          "named" => named_kinds(kinds.fetch(:named)),
          "named_nonterminals" => kinds.fetch(:named_nonterminals).sort.map do |kind_id, symbol_id|
            { "kind_id" => kind_id, "symbol_id" => symbol_id }
          end,
          "trivia" => named_kinds(kinds.fetch(:trivia)),
          "synthetic" => named_kinds(kinds.fetch(:synthetic))
        }
      end

      # @rbs (untyped values) -> Array[Hash[String, untyped]]
      def named_kinds(values)
        values.sort_by { |_name, id| id }.map { |name, id| { "name" => name, "id" => id } }
      end

      # @rbs (Integer production_id, untyped slot) -> Hash[String, untyped]
      def normalize_cst_slot(production_id, slot)
        fields = slot.fetch(:fields).map do |name, value|
          value = { index: value, extraction: nil } if value.is_a?(Integer)
          { "name" => name, "index" => value.fetch(:index), "extraction" => value[:extraction]&.to_s }
        end
        {
          "production_id" => production_id,
          "node_kind_id" => slot.fetch(:node_kind),
          "node_name" => slot.fetch(:node_name),
          "fields" => fields
        }
      end
    end
  end
end
