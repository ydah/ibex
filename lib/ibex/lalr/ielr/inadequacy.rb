# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

module Ibex
  module LALR
    module IELR
      Inadequacy = Struct.new(:state, :token, :contributions, :id, keyword_init: true) do
        def initialize(state:, token:, contributions:, id:)
          super(state: state, token: token, contributions: contributions.freeze, id: id)
          freeze
        end
      end

      Annotation = Struct.new(:inadequacy, :matrix, keyword_init: true) do
        def initialize(inadequacy:, matrix:)
          super(inadequacy: inadequacy, matrix: matrix.freeze)
          freeze
        end

        def key
          [inadequacy.id, matrix]
        end
      end
    end
  end
end
# steep:ignore:end
