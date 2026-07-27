# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  # Optional example-keyed error-message support for parser generation.
  module CLIGenerationErrorMessages
    # @rbs!
    #   private def record_generation_input: (String, String) -> GenerationInput

    private

    # @rbs (OptionParser options) -> void
    def add_error_messages_generation_option(options)
      options.on("--messages=FILE", "embed example-keyed syntax error messages") do |value|
        @options[:messages] = value
      end
    end

    # @rbs (IR::Automaton automaton) -> Hash[Integer, untyped]
    def configured_error_messages(automaton)
      path = @options[:messages]
      return {} unless path

      require_relative "../error_messages"
      source = File.binread(path)
      record_generation_input(path, source)
      document = ErrorMessages.parse(source, file: path)
      ErrorMessages.records_for(document, automaton, file: path)
    end

    # @rbs () -> void
    def validate_messages_options
      return unless @options[:messages]
      raise Ibex::Error, "(cli):1:1: --messages is available only with --emit=ruby" unless @options[:emit] == "ruby"

      raise Ibex::Error, "(cli):1:1: --messages cannot be combined with --check-only" if @options[:check_only]
    end
  end
end
