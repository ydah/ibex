# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

module Ibex
  module LALR
    module IELR
      # @rbs skip
      Inadequacy = Struct.new(:state, :token, :contributions, :id, keyword_init: true) do
        def initialize(state:, token:, contributions:, id:)
          super(state: state, token: token, contributions: contributions.freeze, id: id)
          freeze
        end
      end

      # @rbs skip
      Annotation = Struct.new(:inadequacy, :matrix, keyword_init: true) do
        def initialize(inadequacy:, matrix:)
          super(inadequacy: inadequacy, matrix: matrix.freeze)
          freeze
        end

        def key
          [inadequacy.id, matrix]
        end
      end

      # @rbs!
      #   type contribution = [Symbol, Integer?]
      #   class Inadequacy < Struct[Integer | Array[contribution]]
      #     attr_accessor state: Integer
      #     attr_accessor token: Integer
      #     attr_accessor contributions: Array[contribution]
      #     attr_accessor id: Integer
      #     def self.new: (state: Integer, token: Integer, contributions: Array[contribution], id: Integer) -> instance
      #   end
      #   class Annotation < Struct[Inadequacy | Array[Integer?]]
      #     attr_accessor inadequacy: Inadequacy
      #     attr_accessor matrix: Array[Integer?]
      #     def self.new: (inadequacy: Inadequacy, matrix: Array[Integer?]) -> instance
      #     def key: () -> [Integer, Array[Integer?]]
      #   end
    end
  end
end
# steep:ignore:end
