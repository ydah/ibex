# frozen_string_literal: true

require "fileutils"

module BenchmarkSupport
  # Materializes one fixed public grammar in an isolated benchmark workspace.
  class PublicWorkloadWorkspace
    attr_reader :grammar, :output

    def initialize(directory:, workload:, checkout:)
      @directory = directory
      @workload = workload
      @checkout = checkout
    end

    def prepare
      relative = @workload.fetch("grammar_path")
      @grammar = File.join(@directory, relative)
      @output = @grammar.sub(/\.y\z/, ".rb")
      FileUtils.mkdir_p(File.dirname(@grammar))
      FileUtils.cp(File.join(@checkout, relative), @grammar)
      copy_runtime_neighbor(relative)
      self
    end

    private

    def copy_runtime_neighbor(grammar_path)
      return unless @workload.fetch("id") == "nokogiri_css"

      relative = File.join(File.dirname(grammar_path), "parser_extras.rb")
      FileUtils.cp(File.join(@checkout, relative), File.join(@directory, relative))
    end
  end
end
