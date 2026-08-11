# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module LALR
    module IELR
      # @rbs skip
      SplitState = Struct.new(:core, :transitions, :lalr_isocore, keyword_init: true)

      # @rbs!
      #   class SplitState < Struct[Array[item_core] | Array[[Integer, Integer]] | Integer]
      #     attr_accessor core: Array[item_core]
      #     attr_accessor transitions: Array[[Integer, Integer]]
      #     attr_accessor lalr_isocore: Integer
      #     def self.new: (core: Array[item_core], transitions: Array[[Integer, Integer]],
      #       lalr_isocore: Integer) -> instance
      #   end
    end
  end
end
