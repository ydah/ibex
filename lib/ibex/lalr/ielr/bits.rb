# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

module Ibex
  module LALR
    module IELR
      module Bits
        module_function

        # @rbs (Integer bits) { (Integer) -> void } -> void
        # @rbs (Integer bits) -> Enumerator[Integer, void]
        def each_set_bit(bits)
          return enum_for(:each_set_bit, bits) unless block_given?

          index = 0
          while bits.positive?
            yield index if bits.odd?
            bits >>= 1
            index += 1
          end
        end
      end
    end
  end
end
# steep:ignore:end
