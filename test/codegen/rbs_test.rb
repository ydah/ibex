# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "tmpdir"

class RBSCodegenTest < Minitest::Test
  TYPE_GEMFILE = File.expand_path("../../gemfiles/Gemfile", __dir__)

  def test_generates_namespaced_parser_contract
    source = "class API::Generated < Custom::Parser\nrule\nstart: TOKEN\nend\n"
    ast = Ibex::Frontend::Parser.new(source, file: "signature.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    signature = Ibex::Codegen::RBS.new(automaton).generate

    assert_includes signature, "module API"
    assert_includes signature, "class Generated < Custom::Parser"
    assert_includes signature, "PARSER_TABLE_FORMAT_VERSION: Integer"
    assert_includes signature, "GRAMMAR_DIGEST: String"
    assert_includes signature, "STATE_COUNT: Integer"
    assert_includes signature, "PRODUCTION_COUNT: Integer"
    assert_includes signature, "TOKEN_IDS: Hash[untyped, Integer]"
    assert_includes signature, "DEFAULT_ACTIONS: Array[untyped]"
    assert_includes signature, "ERROR_MESSAGES: Hash[Integer, String | { id: String, message: String }]"
    assert_includes signature, "def self.parser_tables: () -> Hash[Symbol, untyped]"
  end

  def test_generates_private_typed_action_contracts_with_sound_fallbacks
    source = <<~GRAMMAR
      class TypedParser
      pragma extended
      type NUM "Integer"
      type expression "String"
      rule
      expression: NUM TOKEN { result = val[0].to_s + val[1].to_s }
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "typed.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    signature = Ibex::Codegen::RBS.new(automaton).generate

    assert_includes signature,
                    "private def _ibex_action_0: (Integer, untyped) -> String"
  end

  def test_generates_typed_constructor_parameter_contract
    source = <<~GRAMMAR
      class ParameterizedParser
      pragma extended
      %param context "Hash[Symbol, Integer]"
      %param lexer
      type TOKEN "Integer"
      %printer TOKEN { value.to_s }
      rule
      start: TOKEN { result = context.fetch(:offset) + lexer.fetch(:factor) }
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "params.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    signature = Ibex::Codegen::RBS.new(automaton).generate

    assert_includes signature, "@context: Hash[Symbol, Integer]"
    assert_includes signature, "@lexer: untyped"
    assert_includes signature,
                    "def initialize: (context: Hash[Symbol, Integer], lexer: untyped, **untyped) -> void"
    assert_match(/private def _ibex_value_printer_\d+: \(Integer value\) -> untyped/, signature)
    assert_rbs_valid(signature)
  end

  def test_generates_contracts_for_requested_implicit_action_methods
    source = "class TypedParser\nrule\nstart: TOKEN\nend\n"
    ast = Ibex::Frontend::Parser.new(source, file: "typed.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    signature = Ibex::Codegen::RBS.new(automaton, omit_action_call: false).generate

    assert_includes signature,
                    "private def _ibex_action_0: (untyped) -> untyped"
  end

  def test_composed_action_contract_uses_flattened_rhs_and_runtime_lookahead
    source = <<~GRAMMAR
      class InlineTypedParser
      pragma extended
      type TOKEN "Integer"
      type helper "Integer"
      type start "String"
      rule
      %inline helper: TOKEN { result = val[0] + 1 }
      start: helper helper { result = val.join }
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "inline-typed.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    signature = Ibex::Codegen::RBS.new(automaton).generate

    assert_includes signature,
                    "private def _ibex_action_0: ([Integer, Integer], Array[untyped], [untyped, untyped], " \
                    "Array[untyped], Ibex::Runtime::LocationSpan?, untyped) -> String"
    assert_includes signature,
                    "private def _ibex_inline_fragment_0_0: ([Integer], Array[untyped], [untyped], " \
                    "Array[untyped], Ibex::Runtime::LocationSpan?) -> Integer"
    assert_includes signature,
                    "private def _ibex_inline_fragment_0_1: ([Integer], Array[untyped], [untyped], " \
                    "Array[untyped], Ibex::Runtime::LocationSpan?) -> Integer"
    assert_includes signature,
                    "private def _ibex_inline_fragment_0_2: ([Integer, Integer], Array[untyped], " \
                    "[untyped, untyped], Array[untyped], Ibex::Runtime::LocationSpan?) -> String"
    assert_rbs_valid(signature)
  end

  def test_generated_metadata_signatures_pass_rbs_validation
    source = <<~GRAMMAR
      class TypedParser
      pragma extended
      type TOKEN "Array[String | nil]"
      type start "([Integer, String] | nil)"
      rule
      start: TOKEN { result = nil }
           | { result = nil }
      implicit: TOKEN
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "typed-validation.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    explicit = Ibex::Codegen::RBS.new(automaton).generate
    implicit = Ibex::Codegen::RBS.new(automaton, omit_action_call: false).generate

    assert_includes explicit,
                    "private def _ibex_action_0: (Array[String | nil]) -> ([Integer, String] | nil)"
    assert_includes explicit,
                    "private def _ibex_action_1: () -> ([Integer, String] | nil)"
    refute_includes explicit, "private def _ibex_action_2:"
    assert_includes implicit,
                    "private def _ibex_action_2: (Array[String | nil]) -> untyped"

    assert_rbs_valid(explicit)
    assert_rbs_valid(implicit)
  end

  private

  def assert_rbs_valid(signature)
    environment = { "BUNDLE_GEMFILE" => TYPE_GEMFILE }
    available = system(environment, "bundle", "check", out: File::NULL, err: File::NULL)
    skip "the optional RBS toolchain is not installed" unless available

    Dir.mktmpdir("ibex-generated-rbs") do |directory|
      File.write(File.join(directory, "runtime.rbs"), <<~RBS)
        module Ibex
          module Runtime
            class LocationSpan
            end
            class Parser
            end
          end
        end
      RBS
      File.write(File.join(directory, "generated.rbs"), signature)
      stdout, stderr, status = Open3.capture3(
        environment, "bundle", "exec", "rbs", "-I", directory, "validate"
      )
      assert status.success?, "RBS validation failed:\n#{stderr}\n#{stdout}\n#{signature}"
    end
  end
end
