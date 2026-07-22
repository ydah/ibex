# frozen_string_literal: true

require_relative "../test_helper"

class LineConversionTest < Minitest::Test
  def test_user_code_line_mapping_modes_match_compatible_boundaries
    default_parser, default_container = evaluate_with_container(generate, "LineMappingParser")
    assert_user_code_mapping(default_parser, default_container, header: false, inner: true, footer: false)

    all_parser, all_container = evaluate_with_container(generate(line_convert_all: true), "LineMappingParser")
    assert_user_code_mapping(all_parser, all_container, header: true, inner: true, footer: true)

    direct_parser, direct_container = evaluate_with_container(generate(line_convert: false), "LineMappingParser")
    assert_user_code_mapping(direct_parser, direct_container, header: false, inner: false, footer: false)
  end

  def test_line_convert_all_rejects_legacy_ir_without_user_code_locations
    grammar = normalized_grammar
    serialized = JSON.parse(Ibex::IR::Serialize.dump(grammar))
    serialized.delete("user_code_chunks")
    legacy_grammar = Ibex::IR::Serialize.load(JSON.generate(serialized))
    automaton = Ibex::LALR::Builder.new(legacy_grammar).build

    error = assert_raises(Ibex::Error) do
      Ibex::Codegen::Ruby.new(automaton, line_convert_all: true).generate
    end
    assert_equal "(codegen):1:1: source locations are required to convert header user code", error.message
  end

  private

  def generate(**options)
    automaton = Ibex::LALR::Builder.new(normalized_grammar).build
    Ibex::Codegen::Ruby.new(automaton, **options).generate
  end

  def normalized_grammar
    ast = Ibex::Frontend::Parser.new(line_mapping_source, file: "mapping.y").parse
    Ibex::Normalizer.new(ast).normalize
  end

  def evaluate_with_container(source, class_name)
    container = Module.new
    container.module_eval(source, "generated.rb")
    [container.const_get(class_name), container]
  end

  def line_mapping_source
    <<~GRAMMAR
      class LineMappingParser
      rule
      start: TOKEN
      end
      ---- header
      HEADER_FAILURE = proc { raise "header" }
      ---- inner
      def inner_failure = raise("inner")
      ---- footer
      FOOTER_FAILURE = proc { raise "footer" }
    GRAMMAR
  end

  def assert_user_code_mapping(parser_class, container, header:, inner:, footer:)
    failures = {
      header: -> { container.const_get(:HEADER_FAILURE).call },
      inner: -> { parser_class.new.inner_failure },
      footer: -> { container.const_get(:FOOTER_FAILURE).call }
    }
    source_lines = { header: 6, inner: 8, footer: 10 }
    { header: header, inner: inner, footer: footer }.each do |name, mapped|
      error = assert_raises(RuntimeError, &failures.fetch(name))
      if mapped
        assert_match(/mapping\.y:#{source_lines.fetch(name)}:/, error.backtrace.first)
      else
        refute_match(/mapping\.y:/, error.backtrace.first)
      end
    end
  end
end
