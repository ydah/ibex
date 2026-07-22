# frozen_string_literal: true

require_relative "../test_helper"

class FrontendDSLTest < Minitest::Test
  def test_text_and_dsl_frontends_produce_semantically_equal_ir
    text = <<~GRAMMAR
      class DSLCalc
      token NUM
      preclow
      left '+'
      prechigh
      start expr
      rule
      expr: expr '+' expr { result = val[0] + val[2] }
          | NUM { result = val[0] }
      end
      ---- inner
      def marker = :text
    GRAMMAR
    text_ast = Ibex::Frontend::Parser.new(text, file: "text.y").parse
    dsl_ast = Ibex::Frontend::DSL.grammar(class_name: "DSLCalc") do |grammar|
      grammar.token(:NUM)
      grammar.precedence { |levels| levels.left("'+'") }
      grammar.start(:expr)
      grammar.rule(:expr) do |rule|
        rule.alt(:expr, "'+'", :expr, action: " result = val[0] + val[2] ")
        rule.alt(:NUM, action: " result = val[0] ")
      end
      grammar.user_code(:inner, "def marker = :text\n")
    end
    text_ir = Ibex::Normalizer.new(text_ast).normalize.to_h
    dsl_ir = Ibex::Normalizer.new(dsl_ast).normalize.to_h
    assert_equal without_locations(text_ir), without_locations(dsl_ir)
  end

  def test_dsl_supports_extended_items_and_named_references
    ast = Ibex::Frontend::DSL.grammar(class_name: "DSLList") do |grammar|
      grammar.rule(:start) do |rule|
        items = grammar.star(grammar.ref(:ITEM, as: :items))
        rule.alt(items, action: " result = items ")
      end
    end
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    user = grammar.productions.last
    assert_equal [{ name: "items", index: 0 }], user.action.named_refs
    assert(grammar.productions.any? { |production| production.origin[:kind] == :star_expansion })
  end

  def test_dsl_supports_nested_groups
    ast = Ibex::Frontend::DSL.grammar(class_name: "DSLGroup") do |grammar|
      grammar.rule(:start) do |rule|
        pair = grammar.group(%i[A B])
        rule.alt(grammar.plus(grammar.group([pair], [:C])))
      end
    end
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    origins = grammar.productions.map { |production| production.origin[:kind] }
    assert_operator origins.count(:group_expansion), :>=, 3
    assert_includes origins, :plus_expansion
  end

  def test_dsl_supports_convert_options_and_user_code
    ast = Ibex::Frontend::DSL.grammar(class_name: "Configured") do |grammar|
      grammar.token(:NUM)
      grammar.options(:no_result_var)
      grammar.expect(2)
      grammar.convert(:NUM, ":number")
      grammar.rule(:start) { |rule| rule.alt(:NUM, action: " val[0] ") }
      grammar.user_code(:header, "HEADER\n")
    end
    ir = Ibex::Normalizer.new(ast).normalize
    refute ir.options[:result_var]
    assert_equal 2, ir.expect
    assert_equal ":number", ir.conversions["NUM"]
    assert_equal "HEADER\n", ir.user_code["header"]
  end

  def test_rule_action_accepts_any_object_with_a_string_representation
    action = Object.new
    action.define_singleton_method(:to_s) { " result = :converted " }
    ast = Ibex::Frontend::DSL.grammar(class_name: "ConvertedAction") do |grammar|
      grammar.rule(:start) { |rule| rule.alt(:TOKEN, action: action) }
    end

    assert_equal " result = :converted ", ast.rules.first.alternatives.first.action.code
  end

  private

  def without_locations(value)
    case value
    when Array then value.map { |item| without_locations(item) }
    when Hash
      value.each_with_object({}) do |(key, item), result|
        result[key] = without_locations(item) unless key.to_sym == :loc
      end
    else value
    end
  end
end
