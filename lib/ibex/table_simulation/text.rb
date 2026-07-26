# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module TableSimulation
    # Stable one-line renderer for simulation steps.
    module Text
      class << self
        # @rbs (Step step) -> String
        def render_step(step)
          detail = case step.action
                   when "shift" then " target=#{step.target_state}"
                   when "reduce"
                     " production=#{step.production_id} lhs=#{step.lhs} rhs=#{step.rhs_length} " \
                     "goto=#{step.target_state}"
                   else ""
                   end
          "#{step.sequence}: state=#{step.state} token=#{step.token.inspect} action=#{step.action}" \
            "#{detail} source=#{step.action_source} stack=#{step.stack_depth_before}->#{step.stack_depth_after}"
        end

        # @rbs (Result result) -> String
        def render(result)
          lines = result.steps.map { |step| render_step(step) }
          lines << "status=#{result.status}"
          "#{lines.join("\n")}\n"
        end
      end
    end
  end
end
