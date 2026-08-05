# frozen_string_literal: true

module Ibex
  # Files, warnings, and progress emitted by CLI pipeline stages.
  module CLIOutputs
    # @rbs!
    #   private def register_artifact: (Symbol, String, String, ?mode: Integer?, ?status: bool) -> Artifact
    #   private def configuration_value: (String) -> untyped

    WARNING_MESSAGE_IDS = {
      undeclared_terminal: "warning.undeclared_terminal",
      unused_terminal: "warning.unused_terminal",
      unused_precedence: "warning.unused_precedence",
      unreachable_terminal: "warning.unreachable_terminal",
      unreachable_nonterminal: "warning.unreachable_nonterminal",
      duplicate_production: "warning.duplicate_production",
      implicit_empty: "warning.implicit_empty",
      empty_language: "warning.empty_language",
      lexer_redos: "warning.lexer_redos"
    }.freeze #: Hash[Symbol, String]

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

      if categories.include?(:error)
        promoted = grammar.warnings.map do |warning|
          format_grammar_warning(warning, input_path, promoted: true)
        end
        raise Ibex::Error, promoted.join("\n")
      end

      grammar.warnings.each { |warning| @stderr.puts(format_grammar_warning(warning, input_path)) }
    end

    # @rbs (IR::grammar_warning warning, String input_path, ?promoted: bool) -> String
    def format_grammar_warning(warning, input_path, promoted: false)
      location = warning[:loc]
      rendered = if location
                   "#{location[:file] || input_path}:#{location[:line] || 1}:#{location[:column] || 1}"
                 else
                   "#{input_path}:1:1"
                 end
      label_id = promoted ? "label.warning_as_error" : "label.warning"
      label = Messages.translate(label_id, language: @language)
      "#{rendered}: #{label}: #{grammar_warning_message(warning)}"
    end

    # @rbs (IR::grammar_warning warning) -> String
    def grammar_warning_message(warning)
      id = WARNING_MESSAGE_IDS.fetch(warning[:type])
      id = "warning.lexer_redos_symbol" if warning[:type] == :lexer_redos && warning[:symbol]
      Messages.translate(id, language: @language, **warning)
    end

    # @rbs (IR::Automaton automaton, String input_path) -> void
    def report_conflicts(automaton, input_path)
      messages = conflict_messages(automaton.conflict_summary, input_path)
      if @options[:warnings]&.include?(:error) && messages.any?
        promoted = messages.map do |message|
          Messages.translate("conflict.treated_as_error", language: @language, detail: message)
        end
        raise Ibex::Error, promoted.join("\n")
      end

      messages.each { |message| @stderr.puts(message) }
    end

    # @rbs (IR::conflict_summary summary, String input_path) -> Array[String]
    def conflict_messages(summary, input_path)
      messages = [] #: Array[String]
      unless summary[:expectation_met]
        detail = Messages.translate(
          "conflict.shift_reduce_expected",
          language: @language,
          actual: summary[:sr],
          expected: summary[:expected_sr]
        )
        messages << "#{input_path}:1:1: #{detail}"
      end
      if summary.key?(:rr_expectation_met)
        unless summary[:rr_expectation_met]
          detail = Messages.translate(
            "conflict.reduce_reduce_expected",
            language: @language,
            actual: summary[:rr],
            expected: summary[:expected_rr]
          )
          messages << "#{input_path}:1:1: #{detail}"
        end
      elsif summary[:rr].positive?
        detail = Messages.translate("conflict.reduce_reduce", language: @language, actual: summary[:rr])
        messages << "#{input_path}:1:1: #{detail}"
      end
      messages
    end

    # @rbs (IR::Automaton automaton, String input_path) -> void
    # rubocop:disable Metrics/AbcSize -- the bounded comparison reports each conflict class independently.
    def suggest_ielr(automaton, input_path)
      return unless @options[:suggest_ielr]
      return unless automaton.algorithm == "lalr1"
      return unless configuration_value("parser.algorithm") == :lalr

      summary = automaton.conflict_summary
      return if summary[:expectation_met] && summary.fetch(:rr_expectation_met, summary[:rr].zero?)

      ielr = LALR::Builder.new(
        Configuration::AnalysisGrammar.for_algorithm(automaton.grammar, :ielr),
        algorithm: :ielr, entry_isolation: configuration_value("parser.entries") == :isolated
      ).build
      removed_sr = [summary[:sr] - ielr.conflict_summary[:sr], 0].max
      removed_rr = [summary[:rr] - ielr.conflict_summary[:rr], 0].max
      avoided = [] #: Array[String]
      avoided << conflict_count(removed_sr, "shift/reduce") if removed_sr.positive?
      avoided << conflict_count(removed_rr, "reduce/reduce") if removed_rr.positive?
      return if avoided.empty?

      conjunction = @language == "ja" ? "、" : " and "
      detail = Messages.translate("note.ielr", language: @language, avoided: avoided.join(conjunction))
      @stderr.puts("#{input_path}:1:1: #{detail}")
    end
    # rubocop:enable Metrics/AbcSize

    # @rbs (Integer count, String kind) -> String
    def conflict_count(count, kind)
      plural = @language == "en" && count != 1 ? "s" : ""
      Messages.translate("conflict.count", language: @language, count: count, kind: kind, plural: plural)
    end

    # @rbs (IR::Automaton automaton, String input_path) -> void
    def write_report(automaton, input_path)
      require_relative "../codegen/report"
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

    # @rbs (String path, String source) -> void
    def atomic_write_ir(path, source)
      require "tempfile"

      target_path = File.symlink?(path) ? File.realpath(path) : path
      directory = File.dirname(File.expand_path(target_path))
      basename = File.basename(target_path)
      Tempfile.create([".#{basename}.", ".tmp"], directory) do |temporary|
        temporary.binmode
        temporary.write(source)
        temporary.flush
        temporary.fsync
        temporary.chmod(ir_file_mode(target_path))
        temporary.close
        File.rename(temporary.path, target_path)
      end
    end

    # @rbs (String path) -> Integer
    def ir_file_mode(path)
      return File.stat(path).mode & 0o777 if File.exist?(path)

      0o666 & ~File.umask
    end
  end
end
