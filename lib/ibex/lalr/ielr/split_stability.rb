# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

require_relative "bits"

module Ibex
  module LALR
    module IELR
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      module SplitStability
        MAX_ENUMERATED_POTENTIALS = 12

        module_function

        # @rbs (Annotation) -> bool
        def simple?(annotation)
          annotation.matrix.all? { |row| row.nil? || row.zero? }
        end

        # @rbs (Annotation, ConflictResolver) -> bool
        def split_stable?(annotation, resolver)
          return true if simple?(annotation)

          contributions = annotation.inadequacy.contributions
          kept = contributions.each_index.reject { |index| annotation.matrix[index]&.zero? }
          return true if kept.empty?

          potential = kept.reject { |index| annotation.matrix[index].nil? }
          return false if potential.length > MAX_ENUMERATED_POTENTIALS

          base = resolve(resolver, annotation.inadequacy.token, kept.map { |index| contributions[index] })
          subsets(potential).all? do |removed|
            remaining = kept.reject { |index| removed.include?(index) }
            remaining.empty? || resolve(resolver, annotation.inadequacy.token,
                                        remaining.map { |index| contributions[index] }) == base
          end
        end

        # @rbs (ConflictResolver, Integer, Array[Object]) -> Object?
        def resolve(resolver, token, contributions)
          actions = contributions.map do |kind, production_id|
            case kind
            when :shift then { type: :shift, state: 0 }
            when :reduce then { type: :reduce, production: production_id }
            when :accept then { type: :accept }
            when :error then { type: :error }
            else raise Ibex::Error, "unknown IELR contribution #{kind.inspect}"
            end
          end
          action, = resolver.resolve(token, actions)
          normalize(action)
        end

        # @rbs (Object?) -> Object?
        def normalize(action)
          return nil unless action
          return [:shift] if action[:type] == :shift
          return [:reduce, action[:production]] if action[:type] == :reduce
          return [:accept] if action[:type] == :accept
          return [:error] if action[:type] == :error

          action
        end

        # @rbs (Array[Integer]) -> Array[Array[Integer]]
        def subsets(values)
          (0...(1 << values.length)).map do |bits|
            values.each_index.filter_map { |index| values.fetch(index) if bits.anybits?(1 << index) }
          end
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    end
  end
end
# steep:ignore:end
