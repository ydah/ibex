# frozen_string_literal: true

require "json"
require "rbconfig"
require "tempfile"
require "timeout"
require "tmpdir"

module Ibex
  # Executes grammar-declared source examples against one generated parser.
  module GrammarTests
    DEFAULT_TIMEOUT = 10
    RESULT_MARKER = "IBEX_GRAMMAR_TEST_RESULT="

    Result = Struct.new(
      :expectation, #: Symbol
      :actual, #: Symbol
      :error_class, #: String?
      :error_message, #: String?
      :location, #: IR::location
      keyword_init: true
    )

    class Result
      # @rbs () -> bool
      def passed? = expectation == actual
    end

    # Runs all examples in one isolated process while creating a fresh parser
    # instance for every case.
    class Runner
      CHILD_RUNNER = <<~'RUBY'
        require "json"

        load ARGV.fetch(0)
        parser_class = ARGV.fetch(1).split("::").reject(&:empty?).reduce(Object) do |scope, name|
          scope.const_get(name, false)
        end
        tests = JSON.parse(ARGV.fetch(2))
        results = tests.map do |test|
          begin
            parser = parser_class.new
            raise NoMethodError, "#{parser_class} must define parse(source)" unless parser.respond_to?(:parse)

            parser.parse(test.fetch("source"))
            { "actual" => "accept", "error_class" => nil, "error_message" => nil }
          rescue Ibex::Runtime::ParseError => error
            { "actual" => "reject", "error_class" => error.class.name, "error_message" => error.message }
          rescue SystemExit, SignalException, StandardError => error
            { "actual" => "error", "error_class" => error.class.name, "error_message" => error.message }
          end
        end
        puts "IBEX_GRAMMAR_TEST_RESULT=#{JSON.generate(results)}"
      RUBY

      # @rbs @automaton: IR::Automaton
      # @rbs @timeout: Integer

      # @rbs (IR::Automaton automaton, ?timeout: Integer) -> void
      def initialize(automaton, timeout: DEFAULT_TIMEOUT)
        raise ArgumentError, "timeout must be a positive Integer" unless timeout.is_a?(Integer) && timeout.positive?

        @automaton = automaton
        @timeout = timeout
      end

      # @rbs () -> Array[Result]
      def run
        grammar = @automaton.grammar
        raise Ibex::Error, "(test):1:1: grammar declares no %test cases" if grammar.grammar_tests.empty?
        unless grammar.parser_parameters.empty?
          raise Ibex::Error, "(test):1:1: %test cannot instantiate a parser with required %param declarations"
        end

        Dir.mktmpdir("ibex-grammar-tests") do |directory|
          parser_path = File.join(directory, "parser.rb")
          runner_path = File.join(directory, "runner.rb")
          File.binwrite(parser_path, generated_parser)
          File.binwrite(runner_path, CHILD_RUNNER)
          execute_child(parser_path, runner_path)
        end
      end

      private

      # @rbs () -> String
      def generated_parser
        Codegen::Ruby.new(@automaton, table: :compact, embedded: true, line_convert: true).generate
      end

      # @rbs (String parser_path, String runner_path) -> Array[Result]
      def execute_child(parser_path, runner_path)
        payload = JSON.generate(@automaton.grammar.grammar_tests)
        stdout = Tempfile.new("ibex-grammar-test-stdout")
        stderr = Tempfile.new("ibex-grammar-test-stderr")
        stdout_path = stdout.path || raise(Ibex::Error, "(test):1:1: missing temporary stdout path")
        stderr_path = stderr.path || raise(Ibex::Error, "(test):1:1: missing temporary stderr path")
        pid = spawn(
          RbConfig.ruby, runner_path, parser_path, @automaton.grammar.class_name, payload,
          out: stdout_path, err: stderr_path
        )
        status = wait_for_child(pid)
        output = File.binread(stdout_path)
        errors = File.binread(stderr_path)
        raise_child_failure(status, errors) unless status.success?

        decode_results(output)
      ensure
        stdout&.close!
        stderr&.close!
      end

      # @rbs (Integer pid) -> Process::Status
      def wait_for_child(pid)
        Timeout.timeout(@timeout) { Process.wait2(pid).fetch(1) }
      rescue Timeout::Error
        Process.kill("KILL", pid)
        Process.wait(pid)
        raise Ibex::Error, "(test):1:1: grammar tests exceeded #{@timeout} seconds"
      end

      # @rbs (Process::Status status, String errors) -> bot
      def raise_child_failure(status, errors)
        detail = errors.lines.last&.strip
        suffix = detail && !detail.empty? ? ": #{detail}" : ""
        raise Ibex::Error, "(test):1:1: grammar test process exited with status #{status.exitstatus}#{suffix}"
      end

      # @rbs (String output) -> Array[Result]
      def decode_results(output)
        line = output.lines.reverse.find { |candidate| candidate.start_with?(RESULT_MARKER) }
        raise Ibex::Error, "(test):1:1: grammar test process produced no result" unless line

        documents = JSON.parse(line.delete_prefix(RESULT_MARKER).strip)
        tests = @automaton.grammar.grammar_tests
        unless documents.is_a?(Array) && documents.length == tests.length
          raise Ibex::Error, "(test):1:1: grammar test process returned an invalid result count"
        end

        tests.zip(documents).map { |test, document| build_result(test, document) }
      rescue JSON::ParserError, ArgumentError => e
        raise Ibex::Error, "(test):1:1: invalid grammar test process result: #{e.message}"
      end

      # @rbs (IR::grammar_test test, untyped document) -> Result
      def build_result(test, document)
        unless document.is_a?(Hash) && %w[accept reject error].include?(document["actual"])
          raise Ibex::Error, "(test):1:1: grammar test process returned an invalid case result"
        end

        Result.new(
          expectation: test[:expectation], actual: document.fetch("actual").to_sym,
          error_class: document["error_class"], error_message: document["error_message"],
          location: test[:loc]
        ).freeze
      end
    end
  end
end
