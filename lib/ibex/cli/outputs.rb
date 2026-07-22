# frozen_string_literal: true

module Ibex
  # Files, warnings, and progress emitted by CLI pipeline stages.
  module CLIOutputs
    private

    def report_conflicts(automaton, input_path)
      summary = automaton.conflict_summary
      unless summary[:expectation_met]
        @stderr.puts("#{input_path}:1:1: #{summary[:sr]} shift/reduce conflicts; expected #{summary[:expected_sr]}")
      end
      @stderr.puts("#{input_path}:1:1: #{summary[:rr]} reduce/reduce conflicts") if summary[:rr].positive?
    end

    def write_report(automaton, input_path)
      path = @options[:log_file] || default_output_path(input_path, ".output")
      File.write(path, Codegen::Report.render(automaton))
      report_status("wrote #{path}")
    end

    def default_output_path(input_path, extension)
      replaced = input_path.sub(/\.[^.]+\z/, extension)
      replaced == input_path ? "#{input_path}#{extension}" : replaced
    end

    def report_status(message)
      @stderr.puts("ibex: #{message}") if @options[:status]
    end
  end
end
