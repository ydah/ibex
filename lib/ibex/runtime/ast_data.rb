# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # Builds Data classes on Ruby 3.2+ and an immutable Struct-compatible
    # fallback on older supported Rubies.
    module ASTData
      # @rbs (*Symbol members) -> singleton(Object)
      def define(*members)
        return ::Data.define(*members) if defined?(::Data)

        immutable = Module.new
        immutable.send(:define_method, :initialize) do |*arguments, **keywords|
          super(*arguments, **keywords)
          freeze
        end
        Struct.new(*members, keyword_init: true).tap { |node| node.prepend(immutable) }
      end
      module_function :define
    end
  end
end
