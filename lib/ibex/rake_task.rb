# frozen_string_literal: true
# rbs_inline: enabled

require "rake/tasklib"
require_relative "cli"

# @rbs!
#   module Rake
#     class TaskLib
#       def initialize: () -> void
#     end
#
#     class Task
#       def self.define_task: (Hash[String | Symbol, String | Array[String]]) -> Task
#                           | (Hash[String | Symbol, String | Array[String]]) { () -> void } -> Task
#     end
#
#     class FileTask < Task
#     end
#   end

module Ibex
  # Declares grammar-to-parser generation in a Rakefile.
  class RakeTask < Rake::TaskLib
    attr_accessor :grammar #: String?
    attr_accessor :output #: String?
    attr_accessor :options #: Array[String]

    # @rbs (String | Symbol name) ?{ (RakeTask) -> void } -> void
    def initialize(name, &configuration)
      super()
      @name = name
      @grammar = nil
      @output = name.to_s.end_with?(".rb") ? name.to_s : nil
      @options = []
      configuration&.call(self)
      define
    end

    private

    # @rbs () -> void
    def define
      source = @grammar || raise(ArgumentError, "grammar is required")
      target = @output || source.sub(/\.[^.]+\z/, ".rb")
      target = "#{source}.rb" if target == source
      prerequisites = grammar_prerequisites(source)

      Rake::FileTask.define_task(target => prerequisites) do
        status = CLI.start([*@options, "--output-file=#{target}", source])
        raise "parser generation failed for #{source}" unless status.zero?
      end

      Rake::Task.define_task(@name => target) unless @name.to_s == target
    end

    # @rbs (String source) -> Array[String]
    def grammar_prerequisites(source)
      dependencies = Frontend::Resolver.new(source, mode: configured_mode).dependencies
      [source, *dependencies.drop(1)]
    end

    # @rbs () -> Symbol
    def configured_mode
      explicit = @options.find { |option| option.start_with?("--mode=") }
      return explicit.delete_prefix("--mode=").to_sym if explicit

      index = @options.index("--mode")
      index ? @options.fetch(index + 1, "racc").to_sym : :racc
    end
  end
end
