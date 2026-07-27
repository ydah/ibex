# frozen_string_literal: true

module CSTFidelityPropertyHarness
  module_function

  def build(seed:, early: false)
    random = Random.new(seed)
    class_name = "CSTFidelityPropertyParser#{seed}"
    source = early ? early_source(class_name, random) : recovery_source(class_name, random)
    ast = Ibex::Frontend::Parser.new(source, file: "cst-fidelity-#{seed}.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    namespace = Module.new
    namespace.module_eval(Ibex::Codegen::Ruby.new(automaton).generate, "cst_fidelity_property.rb")
    namespace.const_get(grammar.class_name)
  end

  def valid_input(random)
    Array.new(random.rand(1..5)) { "i#{space(random)};#{space(random)}" }.join
  end

  def lexical_error_input(random)
    "i#{space(random)}?#{space(random)};#{space(random)}"
  end

  def recovery_input(random)
    "i#{space(random)}x#{space(random)}x;#{space(random)}i;"
  end

  def repair_input(random)
    "i#{space(random)}i;"
  end

  def early_input(random)
    "i#{space(random)};#{space(random)}i;"
  end

  def recovery_source(class_name, random)
    entry, wrappers = wrapper_rules(random, "statements")
    recursion = if random.rand(2).zero?
                  "statements: statements statement | statement"
                else
                  "statements: statement statements | statement"
                end
    grammar(
      class_name,
      [
        "start: #{entry}",
        *wrappers,
        recursion,
        "statement: ITEM SEMI"
      ]
    )
  end

  def early_source(class_name, random)
    entry, wrappers = wrapper_rules(random, "accepted")
    grammar(
      class_name,
      [
        "start: #{entry}",
        *wrappers,
        "accepted: ITEM { yyaccept } SEMI"
      ]
    )
  end

  def grammar(class_name, rules)
    <<~GRAMMAR
      class #{class_name}
      pragma extended
      pragma cst
      token ITEM BAD SEMI
      %recover sync: SEMI
      lexer
        skip /[[:space:]]+/
        ITEM 'i'
        BAD 'x'
        SEMI ';'
      end
      rule
      #{rules.join("\n")}
      end
    GRAMMAR
  end

  def wrapper_rules(random, target)
    depth = random.rand(4)
    return [target, []] if depth.zero?

    rules = Array.new(depth) do |index|
      child = index == depth - 1 ? target : "layer_#{index + 1}"
      "layer_#{index}: #{child}"
    end
    ["layer_0", rules]
  end

  def space(random)
    ["", " ", "\t", "\n"].fetch(random.rand(4))
  end
end
