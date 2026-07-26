# frozen_string_literal: true

module Ibex
  # Files, warnings, and progress emitted by CLI pipeline stages.
  module CLIOutputs
    # @rbs!
    #   private def register_artifact: (Symbol, String, String, ?mode: Integer?, ?status: bool) -> Artifact

    WARNING_MESSAGES = {
      undeclared_terminal: ->(warning) { "undeclared terminal #{warning[:symbol]}" },
      unused_terminal: ->(warning) { "unused terminal #{warning[:symbol]}" },
      unused_precedence: ->(warning) { "unused precedence #{warning[:symbol]}" },
      unreachable_terminal: ->(warning) { "declared terminal #{warning[:symbol]} is unreachable" },
      unreachable_nonterminal: ->(warning) { "unreachable nonterminal #{warning[:symbol]}" },
      duplicate_production: lambda do |warning|
        "duplicate production #{warning[:production]} (first defined as #{warning[:original]})"
      end,
      implicit_empty: ->(_warning) { "implicit empty alternative; write %empty to document intent" },
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
      messages = conflict_messages(automaton.conflict_summary, input_path)
      if @options[:warnings]&.include?(:error) && messages.any?
        raise Ibex::Error, messages.map { |message| "#{message}; conflict treated as error" }.join("\n")
      end

      messages.each { |message| @stderr.puts(message) }
    end

    # @rbs (IR::conflict_summary summary, String input_path) -> Array[String]
    def conflict_messages(summary, input_path)
      messages = [] #: Array[String]
      unless summary[:expectation_met]
        messages << "#{input_path}:1:1: #{summary[:sr]} shift/reduce conflicts; expected #{summary[:expected_sr]}"
      end
      if summary.key?(:rr_expectation_met)
        unless summary[:rr_expectation_met]
          messages << "#{input_path}:1:1: #{summary[:rr]} reduce/reduce conflicts; expected #{summary[:expected_rr]}"
        end
      elsif summary[:rr].positive?
        messages << "#{input_path}:1:1: #{summary[:rr]} reduce/reduce conflicts"
      end
      messages
    end

    # @rbs (IR::Automaton automaton, String input_path) -> void
    def suggest_ielr(automaton, input_path)
      return unless automaton.algorithm == "lalr1"
      return unless [nil, :lalr].include?(@options[:algorithm])

      summary = automaton.conflict_summary
      return if summary[:expectation_met] && summary.fetch(:rr_expectation_met, summary[:rr].zero?)

      ielr = LALR::Builder.new(
        automaton.grammar, algorithm: :ielr, entry_isolation: @options[:entry_isolation] == true
      ).build
      removed_sr = [summary[:sr] - ielr.conflict_summary[:sr], 0].max
      removed_rr = [summary[:rr] - ielr.conflict_summary[:rr], 0].max
      avoided = [] #: Array[String]
      avoided << conflict_count(removed_sr, "shift/reduce") if removed_sr.positive?
      avoided << conflict_count(removed_rr, "reduce/reduce") if removed_rr.positive?
      return if avoided.empty?

      @stderr.puts("#{input_path}:1:1: note: --algorithm=ielr avoids #{avoided.join(' and ')}; " \
                   "consider --algorithm=ielr")
    end

    # @rbs (Integer count, String kind) -> String
    def conflict_count(count, kind)
      "#{count} #{kind} conflict#{'s' unless count == 1}"
    end

    # @rbs (IR::Automaton automaton, String input_path) -> void
    def write_report(automaton, input_path)
      path = @options[:log_file] || default_output_path(input_path, ".output")
      report = Codegen::Report.render(
        automaton,
        max_tokens: @options[:counterexample_max_tokens],
        max_configurations: @options[:counterexample_max_configurations]
      )
      register_artifact(:report, path, report, status: true)
    end

    # @rbs (String input_path, String extension) -> String
    def default_output_path(input_path, extension)
      directory = File.dirname(input_path)
      basename = File.basename(input_path)
      replaced = basename.sub(/\.[^.]+\z/, extension)
      replaced = "#{basename}#{extension}" if replaced == basename
      directory == "." ? replaced : File.join(directory, replaced)
    end

    # @rbs (String message) -> void
    def report_status(message)
      @stderr.puts("ibex: #{message}") if @options[:status]
    end
  end
end
