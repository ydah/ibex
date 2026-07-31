# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  # Versioned machine and terminal reports for bounded delta reduction.
  module CLIReduceReporting
    # @rbs @reduction_mode: Symbol
    # @rbs @reduction_bounds: reduction_bounds

    private

    # @rbs (DeltaReducer::Result result) -> reduction_success_document
    def reduction_success_report(result)
      items = result.items #: Array[String | Integer]
      {
        ibex_report: "reduce", schema_version: 2,
        result: result.complete ? "minimized" : "incomplete",
        mode: @reduction_mode, original_size: result.original_size,
        minimized_size: items.length, trials: result.trials,
        complete: result.complete, minimized: items, bounded: true,
        bounds: @reduction_bounds
      }
    end

    # @rbs (reduction_budget_details details) -> reduction_budget_document
    def reduction_budget_report(details)
      {
        ibex_report: "reduce", schema_version: 2, result: "budget_exhausted",
        mode: @reduction_mode || @options.fetch(:reduce_mode, :tokens),
        bounded: true, bounds: @reduction_bounds || default_reduction_bounds,
        budget: details
      }
    end

    # @rbs () -> reduction_bounds
    def default_reduction_bounds
      {
        max_trials: @options.fetch(:reduce_max_trials, 1_000),
        timeout_seconds: @options.fetch(:reduce_timeout, BoundedSubprocess::DEFAULT_TIMEOUT_SECONDS),
        max_output_bytes: @options.fetch(
          :reduce_max_output_bytes, BoundedSubprocess::DEFAULT_MAX_OUTPUT_BYTES
        ),
        max_input_bytes: @options.fetch(:reduce_max_input_bytes, CLIReduce::DEFAULT_MAX_INPUT_BYTES)
      }
    end

    # @rbs (reduction_success_document report) -> void
    def write_reduction_success(report)
      if @options.fetch(:reduce_format, "json") == "json"
        @stdout.puts JSON.pretty_generate(report)
        return
      end

      @stdout.puts("result=#{report[:result]}")
      @stdout.puts("mode=#{report[:mode]} original_size=#{report[:original_size]} " \
                   "minimized_size=#{report[:minimized_size]} trials=#{report[:trials]}")
      @stdout.puts("minimized=#{report[:minimized].inspect}")
    end

    # @rbs (reduction_budget_document report) -> void
    def write_reduction_budget(report)
      if @options.fetch(:reduce_format, "json") == "json"
        @stdout.puts JSON.pretty_generate(report)
        return
      end

      @stdout.puts("result=#{report[:result]}")
      @stdout.puts("budget=#{report[:budget].inspect}")
    end
  end
end
