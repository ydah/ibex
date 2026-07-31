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
          invalid = invalid_inputs(directory)
          expected = expected_errors(directory, invalid)
          ALGORITHMS.product(TABLES).each do |algorithm, table|
            parser_class, = compile(directory, algorithm, table)
            valid_inputs(directory).each { |path| parser_class.new.parse(File.binread(path), file: relative(path)) }
            invalid.each do |path|
              assert_rejected(parser_class, path, expected.fetch(File.basename(path)))
            end
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
        messages = gallery_error_messages(directory, automaton)
        namespace = Module.new
        generated = Codegen::Ruby.new(automaton, table: table, error_messages: messages).generate
        namespace.module_eval(generated, relative(path))
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

      def expected_errors(directory, invalid)
        path = File.join(directory, "expected/errors.json")
        document = JSON.parse(File.binread(path))
        names = invalid.map { |entry| File.basename(entry) }.sort
        unless document.keys.sort == names
          raise Ibex::Error,
                "#{relative(path)} must describe every invalid input exactly once " \
                "(expected #{names.inspect}, got #{document.keys.sort.inspect})"
        end
        document
      end

      def gallery_error_messages(directory, automaton)
        path = File.join(directory, "grammar.messages")
        document = ErrorMessages.load(path)
        ErrorMessages.records_for(document, automaton, file: relative(path))
      end

      def assert_rejected(parser_class, path, expected)
        parser_class.new.parse(File.binread(path), file: relative(path))
        raise Ibex::Error, "#{relative(path)} was expected to be rejected"
      rescue Runtime::ParseError => e
        location = e.location || {}
        actual = {
          "error_id" => e.error_id,
          "token" => e.token_name,
          "line" => location[:line],
          "column" => location[:column],
          "expected_tokens" => e.expected_tokens
        }
        return if actual == expected

        raise Ibex::Error,
              "#{relative(path)} error contract differs\n" \
              "expected: #{expected.inspect}\nactual:   #{actual.inspect}"
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
