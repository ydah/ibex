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
#       def self.define_task: (Hash[String | Symbol, String]) -> Task
#                           | (Hash[String | Symbol, String]) { () -> void } -> Task
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

      Rake::FileTask.define_task(target => source) do
        status = CLI.start([*@options, "--output-file=#{target}", source])
        raise "parser generation failed for #{source}" unless status.zero?
      end

      Rake::Task.define_task(@name => target) unless @name.to_s == target
    end
  end
end
