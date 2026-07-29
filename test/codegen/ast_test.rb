# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "tmpdir"

class ASTCodegenTest < Minitest::Test
  TYPE_GEMFILE = File.expand_path("../../Gemfile", __dir__)
  SOURCE = <<~GRAMMAR
    class GeneratedASTParser
    pragma extended
    token NUM PLUS
    type NUM "Integer"
    type PLUS "String"
    lexer
      skip /[[:space:]]+/
      NUM /[0-9]+/ { lexeme.to_i }
      PLUS '+'
    end
    rule
    start: expression @node Root(value)
    expression: NUM PLUS NUM @node Addition(left, operator, right)
    end
  GRAMMAR

  def test_generates_data_nodes_and_constructs_them_from_reductions
    parser_class, = generated
    tree = parser_class.new.parse("1 + 2")

    assert_instance_of parser_class::AST::Root, tree
    assert_instance_of parser_class::AST::Addition, tree.value
    assert_equal [1, "+", 2], tree.value.deconstruct
    assert_equal({ left: 1, operator: "+", right: 2 }, tree.value.deconstruct_keys(nil))
    assert_predicate tree, :frozen?
  end

  def test_generated_visitor_and_listener_cover_every_node_type
    parser_class, = generated
    tree = parser_class.new.parse("1 + 2")
    visited = []
    visitor = Class.new(parser_class::AST::Visitor) do
      define_method(:visit_root) do |node|
        visited << :root
        super(node)
      end
      define_method(:visit_addition) do |node|
        visited << :addition
        super(node)
      end
    end.new
    events = []
    listener = Class.new(parser_class::AST::Listener) do
      define_method(:enter_root) { |_node| events << :enter_root }
      define_method(:exit_root) { |_node| events << :exit_root }
      define_method(:enter_addition) { |_node| events << :enter_addition }
      define_method(:exit_addition) { |_node| events << :exit_addition }
    end.new

    assert_equal tree, visitor.visit(tree)
    assert_equal %i[root addition], visited
    assert_equal tree, listener.walk(tree)
    assert_equal %i[enter_root enter_addition exit_addition exit_root], events
  end

  def test_rbs_lists_typed_nodes_and_every_traversal_hook
    _, signature = generated

    assert_includes signature, "class Root < Data"
    assert_includes signature, "attr_reader value: AST::Addition"
    assert_includes signature, "attr_reader left: Integer"
    assert_includes signature, "attr_reader operator: String"
    assert_includes signature, "def visit_root: (Root node) -> untyped"
    assert_includes signature, "def visit_addition: (Addition node) -> untyped"
    assert_includes signature, "def enter_addition: (Addition node) -> void"
    assert_includes signature, "def exit_addition: (Addition node) -> void"
  end

  def test_node_metadata_round_trips_through_validated_grammar_ir
    grammar = build_automaton(SOURCE).grammar
    serialized = Ibex::IR::Serialize.dump(grammar)
    loaded = Ibex::IR::Validator.validate(serialized)

    assert_equal serialized, Ibex::IR::Serialize.dump(loaded)
    assert_equal(
      { name: "Root", fields: ["value"], loc: { file: "ast.y", line: 12, column: 19 } },
      loaded.productions.fetch(0).node
    )
  end

  def test_generated_ast_signature_is_consumable_by_a_steep_project
    skip "the optional Steep toolchain is not installed" unless type_toolchain_available?

    _, signature = generated
    Dir.mktmpdir("ibex-ast-steep") do |directory|
      write_steep_project(directory, signature)
      stdout, stderr, status = Open3.capture3(
        { "BUNDLE_GEMFILE" => TYPE_GEMFILE }, "bundle", "exec", "steep", "check", chdir: directory
      )
      assert status.success?, "#{stderr}\n#{stdout}\n#{signature}"
    end
  end

  def test_rejects_unsound_or_conflicting_node_shapes
    action = SOURCE.sub(
      "expression: NUM PLUS NUM @node Addition(left, operator, right)",
      "expression: NUM PLUS NUM { result = val } @node Addition(left, operator, right)"
    )
    wrong_arity = SOURCE.sub("Addition(left, operator, right)", "Addition(left, right)")
    conflicting_rules = <<~RULES.chomp
      expression: NUM PLUS NUM @node Addition(left, operator, right)
                | NUM @node Addition(value)
    RULES
    conflict = SOURCE.sub("expression: NUM PLUS NUM @node Addition(left, operator, right)", conflicting_rules)

    assert_match(/cannot be combined with semantic actions/, normalize_error(action).message)
    assert_match(/declares 2 fields for 3 RHS values/, normalize_error(wrong_arity).message)
    assert_match(/already declared with fields/, normalize_error(conflict).message)
  end

  private

  def generated
    automaton = build_automaton(SOURCE)
    source = Ibex::Codegen::Ruby.new(automaton).generate
    namespace = Module.new
    namespace.module_eval(source, "generated_ast.rb")
    [namespace.const_get(:GeneratedASTParser), Ibex::Codegen::RBS.new(automaton).generate]
  end

  def build_automaton(source)
    ast = Ibex::Frontend::Parser.new(source, file: "ast.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    Ibex::LALR::Builder.new(grammar).build
  end

  def normalize_error(source)
    assert_raises(Ibex::Error) { build_automaton(source) }
  end

  def type_toolchain_available?
    system({ "BUNDLE_GEMFILE" => TYPE_GEMFILE }, "bundle", "exec", "steep", "--version",
           out: File::NULL, err: File::NULL)
  end

  def write_steep_project(directory, signature)
    Dir.mkdir(File.join(directory, "sig"))
    write_steep_configuration(directory)
    write_steep_signatures(directory, signature)
    write_steep_consumer(directory)
  end

  def write_steep_configuration(directory)
    File.write(File.join(directory, "Steepfile"), <<~STEEP)
      target :consumer do
        signature "sig"
        check "consumer.rb"
      end
    STEEP
  end

  def write_steep_signatures(directory, signature)
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
    File.write(File.join(directory, "sig", "consumer.rbs"), <<~RBS)
      class ConsumerVisitor < GeneratedASTParser::AST::Visitor
        def visit_addition: (GeneratedASTParser::AST::Addition node) -> Integer
      end
    RBS
  end

  def write_steep_consumer(directory)
    File.write(File.join(directory, "consumer.rb"), <<~RUBY)
      node = GeneratedASTParser::AST::Addition.new(left: 1, operator: "+", right: 2)
      total = node.left + node.right
      total.to_int

      class ConsumerVisitor < GeneratedASTParser::AST::Visitor
        def visit_addition(node)
          node.left + node.right
        end
      end
    RUBY
  end
end
