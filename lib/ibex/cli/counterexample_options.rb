# frozen_string_literal: true

module Ibex
  # Counterexample report limits and their command-line validation.
  module CLICounterexampleOptions
    DEFAULTS = {
      counterexample_max_tokens: LALR::Counterexample::DEFAULT_MAX_TOKENS,
      counterexample_max_configurations: LALR::Counterexample::DEFAULT_MAX_CONFIGURATIONS
    }.freeze

    private

    def add_counterexample_options(options)
      options.on("--counterexamples", "include conflict counterexamples in a report") { @options[:verbose] = true }
      options.on("--counterexample-max-tokens=N", Integer, "maximum counterexample search token budget") do |value|
        @options[:counterexample_max_tokens] = positive_counterexample_limit(value, "--counterexample-max-tokens")
      end
      options.on(
        "--counterexample-max-configurations=N", Integer, "maximum counterexample search configuration budget"
      ) do |value|
        @options[:counterexample_max_configurations] = positive_counterexample_limit(
          value, "--counterexample-max-configurations"
        )
      end
    end

    def positive_counterexample_limit(value, option)
      if value.positive?
        @options[:verbose] = true
        return value
      end

      raise Ibex::Error, "(cli):1:1: #{option} must be positive"
    end
  end
end
