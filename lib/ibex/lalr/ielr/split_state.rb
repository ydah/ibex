# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module LALR
    module IELR
      SplitState = Struct.new(:core, :transitions, :lalr_isocore, keyword_init: true)
    end
  end
end
