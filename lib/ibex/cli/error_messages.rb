# frozen_string_literal: true

require "tempfile"

module Ibex
  # CLI subcommand and generation-file handling for state-specific errors.
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

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_error_messages_command(arguments)
      parser = error_messages_option_parser
      remaining = parser.parse(arguments)
      return print_help(parser) if @options[:help]
      raise Ibex::Error, "(cli):1:1: errors command requires --update[=FILE]" unless @options[:messages_update]

      input = input_path(remaining)
      automaton = automaton_for_error_messages(input)
      write_error_messages(automaton, input)
      0
    end

    # @rbs () -> OptionParser
    def error_messages_option_parser
      OptionParser.new do |options|
        options.banner = "Usage: ibex errors --update[=FILE] [options] grammarfile"
        options.on("--update[=FILE]", "update messages (defaults to grammar.messages)") do |value|
          @options[:messages_update] = value || true
        end
        options.on("--from=FORMAT", %w[grammar-ir automaton-ir], "resume from IR JSON") do |value|
          @options[:from] = value
        end
        options.on("--mode=MODE", %w[racc extended], "grammar mode") { |value| @options[:mode] = value.to_sym }
        options.on("--algorithm=NAME", %w[slr lalr lr1], "parser construction algorithm") do |value|
          @options[:algorithm] = value.to_sym
          @options[:messages_algorithm_explicit] = true
        end
        options.on("--warnings=CATEGORIES", "all, error, all,error, or none") do |value|
          @options[:warnings] = warning_categories(value)
        end
        options.on("-S", "--output-status", "show pipeline status") { @options[:status] = true }
        options.on("--help", "show help") { @options[:help] = true }
      end
    end

    # @rbs (OptionParser options) -> void
    def add_error_messages_generation_option(options)
      options.on("--messages=FILE", "embed state-specific syntax error messages") do |value|
        @options[:messages] = value
      end
    end

    # @rbs (String input_path) -> IR::Automaton
    def automaton_for_error_messages(input_path)
      return automaton_from_ir_for_messages(input_path) if @options[:from]

      report_status("reading #{input_path}")
      source = File.read(input_path)
      ast = Frontend::Parser.new(source, file: input_path, mode: @options[:mode]).parse
      grammar = Normalizer.new(ast, mode: @options[:mode]).normalize
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

      grammar = value.is_a?(IR::Grammar) ? value : value.grammar
      handle_grammar_warnings(grammar, input_path)
      return build_automaton(value, input_path) if value.is_a?(IR::Grammar)

      prepare_loaded_automaton(value, input_path)
      value
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
      rendered = ErrorMessages.render(automaton, existing: existing)
      target_path = File.symlink?(path) ? File.realpath(path) : path
      directory = File.dirname(File.expand_path(target_path))
      Tempfile.create([".ibex-messages-", ".tmp"], directory, encoding: "UTF-8") do |file|
        file.write(rendered)
        File.chmod(messages_file_mode(target_path), file.path)
        file.flush
        file.fsync
        File.rename(file.path, target_path)
      end
      report_status("wrote #{path}")
    end

    # @rbs (String path) -> Integer
    def messages_file_mode(path)
      return File.stat(path).mode & 0o777 if File.exist?(path)

      0o666 & ~File.umask
    end

    # @rbs (IR::Automaton automaton) -> Hash[Integer, String]
    def configured_error_messages(automaton)
      path = @options[:messages]
      return {} unless path

      document = ErrorMessages.load(path)
      ErrorMessages.messages_for(document, automaton, file: path)
    end

    # @rbs () -> void
    def validate_messages_options
      return unless @options[:messages]
      raise Ibex::Error, "(cli):1:1: --messages is available only with --emit=ruby" unless @options[:emit] == "ruby"

      raise Ibex::Error, "(cli):1:1: --messages cannot be combined with --check-only" if @options[:check_only]
    end
  end
end
