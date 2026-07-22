# frozen_string_literal: true

module Ibex
  # Files, warnings, and progress emitted by CLI pipeline stages.
  module CLIOutputs
    WARNING_MESSAGES = {
      undeclared_terminal: ->(warning) { "undeclared terminal #{warning[:symbol]}" },
      unused_terminal: ->(warning) { "unused terminal #{warning[:symbol]}" },
      unreachable_nonterminal: ->(warning) { "unreachable nonterminal #{warning[:symbol]}" },
      duplicate_production: lambda do |warning|
        "duplicate production #{warning[:production]} (first defined as #{warning[:original]})"
      end,
      empty_language: ->(warning) { "start symbol #{warning[:symbol]} derives no terminal sentence" }
    }.freeze #: Hash[Symbol, ^(IR::grammar_warning) -> String]

    private

    # @rbs (String value) -> Array[Symbol]
    def warning_categories(value)
      categories = value.split(",").map(&:strip).reject(&:empty?).map(&:to_sym)
      unknown = categories - %i[all error none]
      raise OptionParser::InvalidArgument, "unknown warning category #{unknown.first}" if unknown.any?
      if categories.empty? || (categories.include?(:none) && categories.length > 1)
        raise OptionParser::InvalidArgument, "warning category none cannot be combined"
      end

      categories
    end

    # @rbs (IR::Grammar grammar, String input_path) -> void
    def handle_grammar_warnings(grammar, input_path)
      categories = @options[:warnings]
      return if categories.nil? || categories.include?(:none) || grammar.warnings.empty?

      messages = grammar.warnings.map { |warning| format_grammar_warning(warning, input_path) }
      if categories.include?(:error)
        promoted = messages.map { |message| message.sub(": warning:", ": warning treated as error:") }
        raise Ibex::Error, promoted.join("\n")
      end

      messages.each { |message| @stderr.puts(message) }
    end

    # @rbs (IR::grammar_warning warning, String input_path) -> String
    def format_grammar_warning(warning, input_path)
      location = warning[:loc]
      rendered = if location
                   "#{location[:file] || input_path}:#{location[:line] || 1}:#{location[:column] || 1}"
                 else
                   "#{input_path}:1:1"
                 end
      formatter = WARNING_MESSAGES.fetch(warning[:type]) { ->(item) { item[:type].to_s.tr("_", " ") } }
      "#{rendered}: warning: #{formatter.call(warning)}"
    end

    # @rbs (IR::Automaton automaton, String input_path) -> void
    def report_conflicts(automaton, input_path)
      summary = automaton.conflict_summary
      unless summary[:expectation_met]
        @stderr.puts("#{input_path}:1:1: #{summary[:sr]} shift/reduce conflicts; expected #{summary[:expected_sr]}")
      end
      @stderr.puts("#{input_path}:1:1: #{summary[:rr]} reduce/reduce conflicts") if summary[:rr].positive?
    end

    # @rbs (IR::Automaton automaton, String input_path) -> void
    def write_report(automaton, input_path)
      path = @options[:log_file] || default_output_path(input_path, ".output")
      report = Codegen::Report.render(
        automaton,
        max_tokens: @options[:counterexample_max_tokens],
        max_configurations: @options[:counterexample_max_configurations]
      )
      File.write(path, report)
      report_status("wrote #{path}")
    end

    # @rbs (String input_path, String extension) -> String
    def default_output_path(input_path, extension)
      replaced = input_path.sub(/\.[^.]+\z/, extension)
      replaced == input_path ? "#{input_path}#{extension}" : replaced
    end

    # @rbs (String message) -> void
    def report_status(message)
      @stderr.puts("ibex: #{message}") if @options[:status]
    end
  end
end
