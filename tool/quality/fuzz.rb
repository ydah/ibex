# frozen_string_literal: true

require "json"
require_relative "../../lib/ibex"

module Ibex
  module Quality
    # Runs the bounded differential fuzzer over every committed gallery grammar.
    class Fuzz
      def initialize(root: File.expand_path("../..", __dir__), count: 100, output: $stdout)
        @root = root
        @count = count
        @output = output
      end

      def run
        reports = grammar_paths.map.with_index do |path, index|
          grammar = normalize(path)
          report = Ibex::Fuzz.new(
            grammar,
            seed: 20_260_731 + index,
            count: @count,
            max_tokens: 64,
            max_expansions: [@count * 128, Ibex::Samples::DEFAULT_MAX_EXPANSIONS].max,
            coverage_guided: true,
            path_length: 2
          ).run
          @output.puts "fuzz: #{path.delete_prefix("#{@root}/")} (#{@count} generated sentences)"
          report
        end
        reports.freeze
      end

      private

      def grammar_paths
        Dir.glob(File.join(@root, "gallery/*/grammar.y"))
      end

      def normalize(path)
        source = File.binread(path)
        relative = path.delete_prefix("#{@root}/")
        ast = Frontend::Parser.new(source, file: relative, mode: :extended).parse
        Normalizer.new(ast, mode: :extended).normalize
      end
    end
  end
end
