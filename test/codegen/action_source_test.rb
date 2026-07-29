# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "ripper"
require "tmpdir"

class ActionSourceCodegenTest < Minitest::Test
  TYPE_GEMFILE = File.expand_path("../../Gemfile", __dir__)
  GOLDEN = File.expand_path("../fixtures/codegen/action-source.golden", __dir__)

  def test_matches_the_deterministic_golden_source
    automaton = build(<<~GRAMMAR, file: "golden-action.y", mode: :extended)
      class Golden::Parser
      pragma extended
      type NUM "Integer"
      type start "Integer"
      rule
      start: NUM:value {result = value + 1}
      end
    GRAMMAR

    assert_equal File.binread(GOLDEN), Ibex::Codegen::ActionSource.new(automaton).generate
  end

  def test_generates_only_private_semantic_methods_for_nested_and_implicit_actions
    automaton = build(nested_action_grammar, file: "shadow.y", mode: :extended)
    generated = Ibex::Codegen::ActionSource.new(automaton, omit_action_call: false).generate
    signature = Ibex::Codegen::RBS.new(automaton, omit_action_call: false).generate

    assert_includes generated, "module API\nclass ShadowParser"
    assert_match(/^private def _ibex_inline_fragment_\d+_\d+/, generated)
    assert_match(/^private def _ibex_action_\d+/, generated)
    assert_operator generated.scan(/^private def /).length, :>=, 5
    assert_includes signature, "private def _ibex_inline_fragment_"
    assert_includes generated, "Static-check-only semantic action shadow source"
    assert_includes generated, "DO NOT LOAD OR EXECUTE"
    assert_omits_runtime_and_user_code(generated)
    refute_nil Ripper.sexp(generated), generated
  end

  def test_preserves_plain_quoted_and_interpolated_heredoc_tokens_without_indenting_terminators
    source = <<~'GRAMMAR'
      class HeredocShadow
      rule
      start: TOKEN {
        plain = <<PLAIN
      plain #{val[0]}
      PLAIN
        quoted = <<~"QUOTED }"
          quoted #{val[0]}
        QUOTED }
        result = [plain, quoted]
      }
      end
    GRAMMAR
    automaton = build(source, file: "heredoc-shadow.y")
    production = automaton.grammar.productions.fetch(0)
    generated = Ibex::Codegen::ActionSource.new(automaton).generate

    assert_equal heredoc_tokens(production.action.code), heredoc_tokens(generated)
    assert_includes generated, "\nPLAIN\n"
    refute_includes generated, "\n  PLAIN\n"
    assert_includes generated, "\n  QUOTED }\n"
    refute_nil Ripper.sexp(generated), generated
  end

  def test_escapes_control_characters_in_grammar_location_comment
    file = "safe.y\nend\nraise 'injected'"
    generated = Ibex::Codegen::ActionSource.new(
      build("class P\nrule\nstart: TOKEN { result = val[0] }\nend\n", file: file)
    ).generate

    assert_includes generated, %(# Grammar action: "safe.y\\nend\\nraise 'injected'":3:14)
    refute_includes generated, "\nraise 'injected'\n"
    refute_nil Ripper.sexp(generated), generated
  end

  def test_runtime_and_shadow_use_the_same_method_source_for_midrule_named_and_location_references
    source = <<~GRAMMAR
      class SharedBuilder
      pragma extended
      options no_result_var
      rule
      start: A:left { return [left, @1, @$] } B:right { return [val[0], right, @2, @$] }
      end
    GRAMMAR
    automaton = build(source, file: "shared-builder.y", mode: :extended)
    shadow = Ibex::Codegen::ActionSource.new(automaton).generate
    runtime = Ibex::Codegen::Ruby.new(automaton).generate
    builder = Ibex::Codegen::ActionMethodSource.new(automaton.grammar)
    methods = automaton.grammar.productions.filter_map do |production|
      builder.compiled_action_method_source(production) if production.action
    end

    assert_operator methods.length, :>=, 2
    methods.each do |method_source|
      assert_includes shadow, method_source
      assert_includes runtime, method_source.dump
      refute_includes method_source, "result ="
    end
  end

  def test_generated_inline_fragment_passes_steep_and_reports_an_intentional_fragment_type_error
    skip "the optional Steep toolchain is not installed" unless type_toolchain_available?

    valid = typed_shadow("result = val[0] + 1")
    invalid = typed_shadow('result = "not an Integer"')
    assert_steep_result(valid, success: true)
    assert_steep_result(invalid, success: false, message: /Integer|String/)
  end

  private

  def build(source, file:, mode: :default)
    ast = Ibex::Frontend::Parser.new(source, file: file, mode: mode).parse
    grammar = Ibex::Normalizer.new(ast, mode: mode).normalize
    Ibex::LALR::Builder.new(grammar).build
  end

  def heredoc_tokens(source)
    depth = 0
    Ripper.lex(source).filter_map do |_position, event, token, _state|
      if event == :on_heredoc_beg
        depth += 1
        [event, token]
      elsif event == :on_heredoc_end
        depth -= 1
        [event, token]
      elsif event == :on_tstring_content && depth.positive?
        [event, token]
      end
    end
  end

  def nested_action_grammar
    <<~GRAMMAR
      class API::ShadowParser
      pragma extended
      type A "Integer"
      type leaf "Integer"
      type helper "Integer"
      type start "String"
      rule
      %inline leaf(X): X { result = val[0] }
      %inline helper: leaf(A) { result = val[0] + 1 }
      start: helper { result = val[0].to_s }
      empty:
      default: A
      end
      ---- header
      raise "header must not be copied"
      ---- inner
      raise "inner must not be copied"
      ---- footer
      raise "footer must not be copied"
    GRAMMAR
  end

  def assert_omits_runtime_and_user_code(generated)
    refute_includes generated, "< Ibex::Runtime::Parser"
    refute_includes generated, "PARSER_TABLES"
    refute_includes generated, "header must not be copied"
    refute_includes generated, "inner must not be copied"
    refute_includes generated, "footer must not be copied"
  end

  def typed_shadow(action)
    automaton = build(<<~GRAMMAR, file: "typed-shadow.y")
      class TypedShadow
      pragma extended
      type NUM "Integer"
      type helper "Integer"
      type start "Integer"
      rule
      %inline helper: NUM { #{action} }
      start: helper { result = val[0] + 1 }
      end
    GRAMMAR
    source = Ibex::Codegen::ActionSource.new(automaton).generate
    assert_includes source, "private def _ibex_inline_fragment_"
    [source, Ibex::Codegen::RBS.new(automaton).generate]
  end

  def type_toolchain_available?
    system({ "BUNDLE_GEMFILE" => TYPE_GEMFILE }, "bundle", "check", out: File::NULL, err: File::NULL)
  end

  def assert_steep_result(generated, success:, message: nil)
    source, signature = generated
    Dir.mktmpdir("ibex-action-steep") do |directory|
      write_steep_project(directory, source, signature)
      stdout, stderr, status = Open3.capture3(
        { "BUNDLE_GEMFILE" => TYPE_GEMFILE }, "bundle", "exec", "steep", "check", chdir: directory
      )
      details = "#{stderr}\n#{stdout}\n#{source}\n#{signature}"
      success ? assert(status.success?, details) : refute(status.success?, details)
      assert_match message, details if message
    end
  end

  def write_steep_project(directory, source, signature)
    Dir.mkdir(File.join(directory, "lib"))
    Dir.mkdir(File.join(directory, "sig"))
    File.write(File.join(directory, "Steepfile"), <<~STEEP)
      target :action_shadow do
        signature "sig"
        check "lib"
      end
    STEEP
    File.write(File.join(directory, "lib", "typed_shadow.actions.rb"), source)
    File.write(File.join(directory, "sig", "runtime.rbs"), <<~RBS)
      module Ibex
        module Runtime
          class LocationSpan
          end
          class Parser
          end
        end
      end
    RBS
    File.write(File.join(directory, "sig", "generated.rbs"), signature)
  end
end
