# frozen_string_literal: true

require "tempfile"
require_relative "../error_messages"
require_relative "../ir"

module Ibex
  # CLI subcommand and generation-file handling for example-keyed errors.
  module CLIErrorMessages
    # @rbs!
    #   private def print_help: (OptionParser) -> Integer
    #   private def input_path: (Array[String]) -> String
    #   private def warning_categories: (String) -> Array[Symbol]
    #   private def report_status: (String) -> void
    #   private def handle_grammar_warnings: (IR::Grammar, String) -> void
    #   private def build_automaton: (IR::Grammar, String) -> IR::Automaton
    #   private def prepare_loaded_automaton: (IR::Automaton, String) -> void
    #   private def default_output_path: (String, String) -> String
    #   private def same_file_target?: (String, String) -> bool
    #   private def normalize_grammar_path: (String) -> IR::Grammar
    #   private def record_generation_input: (String, String) -> GenerationInput
    #   private def select_configuration_mode: (String) -> void
    #   private def set_configuration_option: (Symbol, untyped) -> void

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_error_messages_command(arguments)
      parser = error_messages_option_parser
      remaining = parser.parse(arguments)
      return print_help(parser) if @options[:help]
      if @options[:messages_list] && @options[:messages_update]
        raise Ibex::Error, "(cli):1:1: errors command accepts only one of --list or --update"
      end
      unless @options[:messages_list] || @options[:messages_update]
        raise Ibex::Error, "(cli):1:1: errors command requires --list or --update[=FILE]"
      end

      input = input_path(remaining)
      automaton = automaton_for_error_messages(input)
      if @options[:messages_list]
        @stdout.write(ErrorMessages.render(automaton, **error_message_search_limits))
      else
        write_error_messages(automaton, input)
      end
      0
    end

    # @rbs () -> OptionParser
    def error_messages_option_parser
      OptionParser.new do |options|
        options.banner = "Usage: ibex errors (--list | --update[=FILE]) [options] grammarfile"
        options.on("--list", "list shortest error sentences on stdout") { @options[:messages_list] = true }
        options.on("--update[=FILE]", "update messages (defaults to grammar.messages)") do |value|
          @options[:messages_update] = value || true
        end
        options.on("--max-tokens=N", Integer, "maximum error-sentence token budget") do |value|
          @options[:messages_max_tokens] = positive_messages_limit(value, "--max-tokens")
        end
        options.on("--max-configurations=N", Integer, "maximum error-sentence configuration budget") do |value|
          @options[:messages_max_configurations] = positive_messages_limit(value, "--max-configurations")
        end
        options.on("--from=FORMAT", %w[grammar-ir automaton-ir], "resume from IR JSON") do |value|
          @options[:from] = value
        end
        options.on("--mode=MODE", %w[default extended], "grammar mode") { |value| select_configuration_mode(value) }
        options.on("--algorithm=NAME", %w[slr lalr ielr lr1], "parser construction algorithm") do |value|
          set_configuration_option(:algorithm, value.to_sym)
          @options[:messages_algorithm_explicit] = true
        end
        options.on("--warnings=CATEGORIES", "all, error, all,error, or none") do |value|
          @options[:warnings] = warning_categories(value)
        end
        options.on("-S", "--output-status", "show pipeline status") { @options[:status] = true }
        options.on("--help", "show help") { @options[:help] = true }
      end
    end

    # @rbs (String input_path) -> IR::Automaton
    def automaton_for_error_messages(input_path)
      return automaton_from_ir_for_messages(input_path) if @options[:from]

      report_status("reading #{input_path}")
      grammar = normalize_grammar_path(input_path)
      grammar = activate_analysis_grammar(grammar)
      handle_grammar_warnings(grammar, input_path)
      build_automaton(grammar, input_path)
    end

    # @rbs (String input_path) -> IR::Automaton
    def automaton_from_ir_for_messages(input_path)
      report_status("reading #{input_path}")
      value = IR::Validator.validate(File.read(input_path))
      expected = @options[:from] == "grammar-ir" ? IR::Grammar : IR::Automaton
      raise Ibex::Error, "#{input_path}:1:1: expected #{@options[:from]} input" unless value.is_a?(expected)
      if value.is_a?(IR::Automaton) && @options[:messages_algorithm_explicit]
        raise Ibex::Error, "(cli):1:1: --algorithm cannot be combined with --from=automaton-ir"
      end

      grammar = if value.is_a?(IR::Grammar)
                  activate_analysis_grammar(value)
                elsif value.is_a?(IR::Automaton)
                  value.grammar
                else
                  raise Ibex::Error, "#{input_path}:1:1: expected #{@options[:from]} input"
                end
      handle_grammar_warnings(grammar, input_path)
      return build_automaton(grammar, input_path) if value.is_a?(IR::Grammar)

      if value.is_a?(IR::Automaton)
        prepare_loaded_automaton(value, input_path)
        return value
      end

      raise Ibex::Error, "#{input_path}:1:1: expected #{@options[:from]} input"
    end

    # @rbs (IR::Automaton automaton, String input_path) -> void
    def write_error_messages(automaton, input_path)
      configured = @options[:messages_update]
      path = configured == true ? default_output_path(input_path, ".messages") : configured
      raise Ibex::Error, "(cli):1:1: messages update path must not be empty" unless path.is_a?(String) && !path.empty?
      if same_file_target?(path, input_path)
        raise Ibex::Error, "(cli):1:1: messages update path must differ from the input path"
      end

      existing = if File.exist?(path)
                   ErrorMessages.load(path)
                 else
                   ErrorMessages::Document.new(entries: [])
                 end
      update = ErrorMessages.update(automaton, existing: existing, **error_message_search_limits)
      target_path = File.symlink?(path) ? File.realpath(path) : path
      directory = File.dirname(File.expand_path(target_path))
      Tempfile.create([".ibex-messages-", ".tmp"], directory, encoding: "UTF-8") do |file|
        file.write(update.source)
        File.chmod(messages_file_mode(target_path), file.path)
        file.flush
        file.fsync
        File.rename(file.path, target_path)
      end
      write_error_message_update_report(update)
      report_status("wrote #{path}")
    end

    # @rbs () -> { max_tokens: Integer, max_configurations: Integer }
    def error_message_search_limits
      {
        max_tokens: @options.fetch(:messages_max_tokens, ErrorMessages::SentenceSearch::DEFAULT_MAX_TOKENS),
        max_configurations: @options.fetch(
          :messages_max_configurations, ErrorMessages::SentenceSearch::DEFAULT_MAX_CONFIGURATIONS
        )
      }
    end

    # @rbs (Integer value, String option) -> Integer
    def positive_messages_limit(value, option)
      return value if value.positive?

      raise Ibex::Error, "(cli):1:1: #{option} must be positive"
    end

    # @rbs (ErrorMessages::Update update) -> void
    def write_error_message_update_report(update)
      classifications = {
        "uncovered" => update.uncovered, "unreachable" => update.unreachable, "moved" => update.moved
      }
      classifications.each do |label, items|
        items.each { |item| @stdout.puts("#{label}: #{item}") }
      end
    end

    # @rbs (String path) -> Integer
    def messages_file_mode(path)
      return File.stat(path).mode & 0o777 if File.exist?(path)

      0o666 & ~File.umask
    end

    # @rbs!
    #   private def activate_analysis_grammar: (IR::Grammar, ?options: Hash[Symbol, untyped],
    #     ?explicit_keys: Array[Symbol]) -> IR::Grammar
  end
end
