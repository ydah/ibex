# frozen_string_literal: true

require "json"
require_relative "../../lib/ibex"

module Ibex
  module Quality
    # Builds and executes the repository-owned grammar gallery.
    class Gallery
      ALGORITHMS = %i[slr lalr ielr lr1].freeze
      TABLES = %i[plain compact].freeze

      def initialize(root: File.expand_path("../..", __dir__), output: $stdout)
        @root = root
        @output = output
      end

      def build!
        directories = grammar_directories
        directories.each do |directory|
          ALGORITHMS.product(TABLES).each do |algorithm, table|
            parser_class, = compile(directory, algorithm, table)
            valid_inputs(directory).each { |path| parser_class.new.parse(File.binread(path), file: relative(path)) }
            invalid_inputs(directory).each { |path| assert_rejected(parser_class, path) }
          end
          @output.puts "gallery build: #{File.basename(directory)}"
        end
        directories.length
      end

      def conflicts!
        directories = grammar_directories
        directories.each do |directory|
          expected_path = File.join(directory, "expected/metrics.json")
          expected = JSON.parse(File.binread(expected_path))
          actual = ALGORITHMS.to_h do |algorithm|
            _, automaton = compile(directory, algorithm, :compact)
            [algorithm.to_s, metrics(automaton)]
          end
          next if actual == expected

          raise Ibex::Error,
                "#{relative(expected_path)} differs\nexpected: #{expected.inspect}\nactual:   #{actual.inspect}"
        end
        @output.puts "gallery conflict and state metrics match"
        directories.length
      end

      def current_metrics
        grammar_directories.to_h do |directory|
          values = ALGORITHMS.to_h do |algorithm|
            _, automaton = compile(directory, algorithm, :compact)
            [algorithm.to_s, metrics(automaton)]
          end
          [File.basename(directory), values]
        end
      end

      private

      def grammar_directories
        Dir.glob(File.join(@root, "gallery/*")).select do |path|
          File.directory?(path) && File.file?(File.join(path, "grammar.y"))
        end.sort
      end

      def compile(directory, algorithm, table)
        path = File.join(directory, "grammar.y")
        source = File.binread(path)
        ast = Frontend::Parser.new(source, file: relative(path), mode: :extended).parse
        grammar = Normalizer.new(ast, mode: :extended).normalize
        builder = LALR::Builder.new(grammar, algorithm: algorithm)
        automaton = builder.build
        namespace = Module.new
        namespace.module_eval(Codegen::Ruby.new(automaton, table: table).generate, relative(path))
        [constant(namespace, grammar.class_name), automaton]
      end

      def constant(namespace, name)
        name.split("::").reject(&:empty?).reduce(namespace) { |scope, part| scope.const_get(part, false) }
      end

      def valid_inputs(directory)
        Dir.glob(File.join(directory, "corpus/*")).select { |path| File.file?(path) }.sort
      end

      def invalid_inputs(directory)
        Dir.glob(File.join(directory, "invalid/*")).select { |path| File.file?(path) }.sort
      end

      def assert_rejected(parser_class, path)
        parser_class.new.parse(File.binread(path), file: relative(path))
        raise Ibex::Error, "#{relative(path)} was expected to be rejected"
      rescue Runtime::ParseError, Ibex::Error
        nil
      end

      def metrics(automaton)
        {
          "states" => automaton.states.length,
          "shift_reduce" => automaton.conflict_summary.fetch(:sr),
          "reduce_reduce" => automaton.conflict_summary.fetch(:rr)
        }
      end

      def relative(path)
        path.delete_prefix("#{@root}/")
      end
    end
  end
end
