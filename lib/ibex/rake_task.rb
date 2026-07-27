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
#                           | (Hash[String | Symbol, String | Array[String]]) {
#                               (untyped, untyped) -> void
#                             } -> Task
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
    attr_accessor :action_source #: String | true | nil

    # @rbs (String | Symbol name) ?{ (RakeTask) -> void } -> void
    def initialize(name, &configuration)
      super()
      @name = name
      @grammar = nil
      @output = name.to_s.end_with?(".rb") ? name.to_s : nil
      @options = []
      @action_source = nil
      configuration&.call(self)
      define
    end

    private

    # @rbs () -> void
    def define
      source = @grammar || raise(ArgumentError, "grammar is required")
      reject_watch_option!
      target = @output || source.sub(/\.[^.]+\z/, ".rb")
      target = "#{source}.rb" if target == source
      prerequisites = grammar_prerequisites(source)
      action_target = configured_action_source(target)
      arguments = [*@options]
      arguments << (@action_source == true ? "--action-source" : "--action-source=#{action_target}") if action_target
      generate = lambda do |_task, _task_arguments|
        status = CLI.start([*arguments, "--output-file=#{target}", source])
        raise "parser generation failed for #{source}" unless status.zero?
      end

      if action_target
        Rake::FileTask.define_task(action_target => prerequisites, &generate)
        Rake::FileTask.define_task(target => [*prerequisites, action_target], &generate)
      else
        Rake::FileTask.define_task(target => prerequisites, &generate)
      end

      Rake::Task.define_task(@name => target) unless @name.to_s == target
    end

    # @rbs () -> void
    def reject_watch_option!
      return unless @options.any? { |option| option == "--watch" || option.start_with?("--watch=") }

      raise ArgumentError, "RakeTask options must not include --watch"
    end

    # @rbs (String target) -> String?
    def configured_action_source(target)
      return nil unless @action_source

      path = @action_source == true ? default_action_source_path(target) : @action_source
      raise ArgumentError, "action_source must be true or a non-empty String" unless
        path.is_a?(String) && !path.empty?
      if File.expand_path(path) == File.expand_path(target)
        raise ArgumentError, "action_source and output must be distinct"
      end

      path
    end

    # @rbs (String target) -> String
    def default_action_source_path(target)
      directory = File.dirname(target)
      basename = File.basename(target)
      replaced = basename.sub(/\.[^.]+\z/, ".actions.rb")
      replaced = "#{basename}.actions.rb" if replaced == basename
      directory == "." ? replaced : File.join(directory, replaced)
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
      index ? @options.fetch(index + 1, "default").to_sym : :default
    end
  end
end
