# frozen_string_literal: true

module Ibex
  # Validation and normalization for generated AST node declarations.
  module NormalizeNodes
    private

    # @rbs (Frontend::AST::Alternative alternative, Array[String] rhs) -> IR::node_annotation?
    def normalize_node_annotation(alternative, rhs)
      # @type self: Normalizer
      annotation = alternative.node_annotation
      return unless annotation

      if alternative.action || alternative.items.any?(Frontend::AST::InlineAction)
        fail_at(annotation.loc, "@node cannot be combined with semantic actions")
      end
      unless annotation.name.match?(/\A[A-Z][A-Za-z0-9_]*\z/)
        fail_at(annotation.loc, "@node name #{annotation.name.inspect} must be a Ruby constant identifier")
      end
      validate_node_fields(annotation, rhs)
      previous = @node_shapes[annotation.name]
      if previous && previous != annotation.fields
        fail_at(annotation.loc, "@node #{annotation.name} was already declared with fields (#{previous.join(', ')})")
      end
      @node_shapes[annotation.name] = annotation.fields.dup.freeze
      { name: annotation.name, fields: annotation.fields, loc: annotation.loc.to_h }
    end

    # @rbs (Frontend::AST::NodeAnnotation annotation, Array[String] rhs) -> void
    def validate_node_fields(annotation, rhs)
      # @type self: Normalizer
      unless annotation.fields.length == rhs.length
        fail_at(
          annotation.loc,
          "@node #{annotation.name} declares #{annotation.fields.length} fields for #{rhs.length} RHS values"
        )
      end
      duplicate = annotation.fields.tally.find { |_name, count| count > 1 }&.first
      fail_at(annotation.loc, "@node field #{duplicate.inspect} is duplicated") if duplicate
      invalid = annotation.fields.find do |field|
        !field.match?(/\A[a-z_][a-zA-Z0-9_]*\z/) || Normalizer::RUBY_KEYWORDS.include?(field)
      end
      fail_at(annotation.loc, "@node field #{invalid.inspect} must be a Ruby local identifier") if invalid
    end
  end
end
