# frozen_string_literal: true
# rbs_inline: enabled

require "json"

module Ibex
  module Runtime
    # Emits committed parser observer events as JSON Lines.
    module JSONLTracer
      # @rbs!
      #   interface _TraceOutput
      #     def puts: (String) -> untyped
      #   end

      # Hook layer installed on an individual parser's singleton class.
      module Hooks
        # @rbs!
        #   def token_to_str: (Integer) -> String

        # @rbs @ibex_jsonl_trace_output: _TraceOutput?

        # @rbs (Integer token_id, untyped value, Integer state) -> void
        def on_shift(token_id, value, state)
          write_trace(event: "shift", token_id: token_id, token: token_to_str(token_id),
                      value: safe_inspect(value), state: state)
          super
        end

        # @rbs (Integer production_id, Array[untyped] values, untyped result) -> void
        def on_reduce(production_id, values, result)
          write_trace(event: "reduce", production_id: production_id, values: values.map { |value| safe_inspect(value) },
                      result: safe_inspect(result))
          super
        end

        # @rbs (Integer token_id, untyped value, Array[untyped] value_stack) -> void
        def on_error_recover(token_id, value, value_stack)
          write_trace(event: "error_recover", token_id: token_id, token: token_to_str(token_id),
                      value: safe_inspect(value), value_stack: value_stack.map { |item| safe_inspect(item) })
          super
        end

        private

        # @rbs (_TraceOutput output) -> void
        def ibex_jsonl_trace_output=(output)
          @ibex_jsonl_trace_output = output
        end

        # @rbs (**untyped event) -> void
        def write_trace(**event)
          @ibex_jsonl_trace_output&.puts(JSON.generate(event))
        rescue StandardError
          nil
        end

        # @rbs (untyped value) -> String
        def safe_inspect(value)
          value.inspect.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        rescue StandardError
          "<inspect failed>"
        end
      end

      # @rbs [P < Parser] (P parser, io: _TraceOutput) -> P
      def self.attach(parser, io:)
        singleton = parser.singleton_class
        singleton.prepend(Hooks) unless singleton.ancestors.include?(Hooks)
        parser.__send__(:ibex_jsonl_trace_output=, io)
        parser
      end
    end
  end
end
