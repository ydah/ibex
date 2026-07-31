# frozen_string_literal: true

require "yaml"
require_relative "../../lib/ibex"

module Ibex
  module TestSupport
    # Runs the declared parser pipeline combinations and reports invariant ids.
    class MatrixRunner
      AXIS_ORDER = %w[algorithm table cst locations entries].freeze
      INVARIANTS = %w[INV1 INV2 INV3 INV4 INV5 INV6].freeze
      def initialize(path: File.expand_path("../matrix.yml", __dir__), output: $stdout)
        @configuration = YAML.safe_load_file(path)
        @output = output
      end

      def run(full: false)
        combinations = declared_combinations
        combinations = representative(combinations) unless full
        observations = {}
        combinations.each_with_index do |combination, index|
          run_combination(combination, observations)
          @output.puts "matrix #{index + 1}/#{combinations.length}: #{label(combination)}"
        rescue StandardError => e
          raise e.class, "#{label(combination)} #{invariant(e)}: #{e.message}", e.backtrace
        end
        verify_node_invariant(combinations)
        combinations.length
      end

      private

      def declared_combinations
        axes = @configuration.fetch("axes")
        values = AXIS_ORDER.map { |axis| axes.fetch(axis) }
        values.shift.product(*values).map { |row| AXIS_ORDER.zip(row).to_h.freeze }.freeze
      end

      def representative(combinations)
        count = Integer(@configuration.fetch("representative"))
        return combinations if count >= combinations.length

        Array.new(count) do |index|
          combinations.fetch((index * combinations.length) / count)
        end
      end

      def run_combination(combination, observations)
        grammar = normalize(grammar_source(combination))
        automaton = build(grammar, combination)
        assert_round_trip(grammar, automaton)
        generated = generated_source(automaton, combination)
        assert_equal_bytes(generated, generated_source(build(normalize(grammar_source(combination)), combination),
                                                       combination), "INV5 generated source")
        parser_class = evaluate(generated)
        observation = observe(parser_class, combination)
        key = combination.values_at("cst", "locations", "entries")
        baseline = observations[key] ||= observation
        assert_value(baseline, observation, "INV1/INV3 algorithm and table behavior")
        assert_resource_limit(parser_class)
      end

      def normalize(source)
        ast = Frontend::Parser.new(source, file: "matrix.y", mode: :extended).parse
        Normalizer.new(ast, mode: :extended).normalize
      end

      def build(grammar, combination)
        LALR::Builder.new(
          grammar,
          algorithm: combination.fetch("algorithm").to_sym,
          entry_isolation: combination.fetch("entries") == "isolated"
        ).build
      end

      def generated_source(automaton, combination)
        Codegen::Ruby.new(automaton, table: combination.fetch("table").to_sym).generate
      end

      def evaluate(source)
        namespace = Module.new
        namespace.module_eval(source, "matrix-generated.rb")
        namespace.const_get(:MatrixParser)
      end

      def observe(parser_class, combination)
        parser = parser_class.new
        value = parser.lex("1 + 2", file: "matrix.input").do_parse

        invalid = parser_class.new
        error = invalid_observation(invalid, combination)
        [value, error].freeze
      end

      def invalid_observation(parser, combination)
        if combination.fetch("cst") == "on"
          diagnostic = parser.parse_with_syntax("+", file: "matrix.input").diagnostics.fetch(0)
          return %i[error_id token_name expected_tokens location].map do |key|
            value = diagnostic_value(diagnostic, key)
            key == :location ? location_tuple(value) : value
          end
        end

        parser.parse("+", file: "matrix.input")
        raise "INV3 invalid sentence was accepted"
      rescue Runtime::ParseError => e
        [e.error_id, e.token_name, e.expected_tokens, location_tuple(e.location)]
      end

      def assert_round_trip(grammar, automaton)
        [grammar, automaton].each do |value|
          serialized = IR::Serialize.dump(value)
          assert_equal_bytes(serialized, IR::Serialize.dump(IR::Serialize.load(serialized)), "INV4 IR round trip")
        end
      end

      def assert_resource_limit(parser_class)
        parser = parser_class.new(resource_limits: Runtime::ResourceLimits.new(max_stack_depth: 2))
        parser.lex("1 + 2", file: "matrix.input").do_parse
        raise "INV6 configured stack limit was not enforced"
      rescue Runtime::ResourceLimitError
        nil
      end

      def verify_node_invariant(combinations)
        combinations.map { |item| item.values_at("algorithm", "table") }.uniq.each do |algorithm, table|
          grammar = normalize(node_source)
          automaton = LALR::Builder.new(grammar, algorithm: algorithm.to_sym).build
          parser_class = evaluate_node(Codegen::Ruby.new(automaton, table: table.to_sym).generate)
          parser = parser_class.new
          parser.tokens = [[:NUM, 1], [:PLUS, "+"], [:NUM, 2]]
          tree = parser.do_parse
          value = [tree.class.name&.split("::")&.last, tree.value.class.name&.split("::")&.last,
                   tree.value.deconstruct]
          @node_baseline ||= value
          assert_value(@node_baseline, value, "INV2 generated AST")
        end
      rescue StandardError => e
        raise e.class, "node matrix INV2: #{e.message}", e.backtrace
      end

      def evaluate_node(source)
        namespace = Module.new
        namespace.module_eval(source, "matrix-node-generated.rb")
        namespace.const_get(:MatrixNodeParser)
      end

      def grammar_source(combination)
        cst = "pragma cst" if combination.fetch("cst") == "on"
        starts = combination.fetch("entries") == "single" ? "" : "start document atom"
        location_action = combination.fetch("locations") == "on" ? "_span = @1;" : ""
        <<~GRAMMAR
          class MatrixParser
          pragma extended
          #{cst}
          #{starts}
          token NUM PLUS
          lexer
            skip /[[:space:]]+/
            NUM /[0-9]+/ { |text| Integer(text, 10) }
            PLUS '+'
          end
          rule
          document: expression { #{location_action} result = val[0] }
          atom: NUM { #{location_action} result = val[0] }
          expression: NUM { #{location_action} result = val[0] }
                    | expression PLUS NUM { #{location_action} result = val[0] + val[2] }
          end
        GRAMMAR
      end

      def node_source
        <<~GRAMMAR
          class MatrixNodeParser
          pragma extended
          token NUM PLUS
          rule
          start: expression @node Root(value)
          expression: NUM PLUS NUM @node Addition(left, operator, right)
          end
          ---- inner
          attr_writer :tokens
          def next_token = @tokens.shift
        GRAMMAR
      end

      def assert_equal_bytes(expected, actual, description)
        return if expected == actual

        offset = first_difference(expected, actual)
        raise "#{description} differs at byte #{offset}"
      end

      def assert_value(expected, actual, description)
        raise "#{description}: expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
      end

      def first_difference(left, right)
        limit = [left.bytesize, right.bytesize].min
        index = 0
        index += 1 while index < limit && left.getbyte(index) == right.getbyte(index)
        index
      end

      def location_tuple(location)
        return unless location

        %i[file line column].map do |key|
          location.respond_to?(key) ? location.public_send(key) : location[key]
        end
      end

      def diagnostic_value(diagnostic, key)
        return diagnostic.public_send(key) if diagnostic.respond_to?(key)

        diagnostic[key] || diagnostic[key.to_s]
      end

      def label(combination)
        AXIS_ORDER.map { |axis| "#{axis}=#{combination.fetch(axis)}" }.join(",")
      end

      def invariant(error)
        INVARIANTS.find { |id| error.message.include?(id) } || "pipeline"
      end
    end
  end
end
