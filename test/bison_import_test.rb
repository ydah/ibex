# frozen_string_literal: true

require_relative "test_helper"

class BisonImportTest < Minitest::Test
  SOURCE = <<~BISON
    %{
    static int helper(void) { return 1; }
    %}
    %define api.pure full
    %token <ival> NUM 258 "number" PLUS "+"
    %left PLUS
    %type <ival> expr
    %start input
    %expect 0
    %glr-parser
    %%
    input:
        expr { $$ = $1; }
      ;
    expr:
        expr PLUS expr { $$ = $1 + $3; }
      | NUM { $$ = $<ival>1; @$ = @1; }
      | %empty
      ;
    %%
    int main(void) { return 0; }
  BISON

  def test_imports_structure_lists_unsupported_and_transforms_action_references
    result = import(SOURCE)
    report = result.to_h

    assert_equal "imported_with_unsupported", report.fetch(:result)
    assert_equal(["glr-parser"], report.fetch(:unsupported).map { |entry| entry.fetch(:name) })
    assert_equal false, report.fetch(:structurally_complete)
    assert_equal(["glr-parser"], report.fetch(:structural_unsupported).map { |entry| entry.fetch(:name) })
    assert_includes result.source, "token NUM \"number\""
    assert_includes result.source, "left PLUS"
    assert_includes result.source, Ibex::BisonImport::FOREIGN_ACTION_SENTINEL
    assert_equal " result = val[0]; ", result.actions.fetch(0).transformed
    assert_equal " result = val[0]; result_loc = @1; ", result.actions.fetch(2).transformed
  end

  def test_imported_source_builds_for_analysis_but_refuses_ruby_generation
    result = import(SOURCE)
    ast = Ibex::Frontend::Parser.new(result.source, file: "imported.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build

    assert_operator automaton.states.length, :>, 0
    error = assert_raises(Ibex::Error) { Ibex::Codegen::Ruby.new(automaton) }
    assert_includes error.message, "cannot generate Ruby from imported C semantic actions"
  end

  def test_every_known_and_unknown_directive_is_positioned_and_classified
    declarations = Ibex::BisonImport::DIRECTIVES.keys.map { |name| "%#{name} VALUE" }.join("\n")
    source = "#{declarations}\n%unknown-directive VALUE\n%%\nstart: ITEM ;\n%%\n"

    directives = import(source).directives
    by_name = directives.to_h { |directive| [directive.name, directive] }

    Ibex::BisonImport::DIRECTIVES.each do |name, status|
      assert_equal status, by_name.fetch(name).status, name
      assert_operator by_name.fetch(name).line, :>, 0
      assert_operator by_name.fetch(name).column, :>, 0
    end
    assert_equal :unsupported, by_name.fetch("unknown-directive").status
  end

  def test_codegen_only_unsupported_directives_do_not_make_structure_incomplete
    source = <<~BISON
      %require "3.8"
      %initial-action { initialize(); }
      %%
      start: ITEM ;
      %%
    BISON

    result = import(source)

    assert result.structurally_complete?
    assert_empty result.structural_unsupported
    assert_includes result.source, "ibex-bison-structural-status: complete"
  end

  def test_nested_actions_are_opaque_and_action_budget_is_distinct
    source = <<~BISON
      %token ITEM
      %%
      start: ITEM { if ($1) { call("{"); } /* } */ $$ = $1; }
           | ITEM { $$ = $1; }
           ;
      %%
    BISON

    result = import(source)
    assert_equal 2, result.actions.length
    assert_includes result.actions.fetch(0).original, 'call("{")'

    error = assert_raises(Ibex::BisonImport::BudgetExceeded) do
      Ibex::BisonImport::Importer.new(
        source, file: "nested.y", max_actions: 1
      ).run
    end
    assert_equal "actions", error.details.fetch(:phase)
  end

  def test_maps_uppercase_keyword_and_named_nonterminals_without_collisions
    source = <<~BISON
      %token keyword_begin keyword_BEGIN import NUM /* ignored comment words */
      %token OP TOKEN_CODE(OP) "operator"
      %start Expr
      %%
      Expr[result]: compstmt[value] keyword_begin
                  | keyword_BEGIN import
                  ;
      compstmt[result]: NUM ;
      %%
    BISON

    result = import(source)
    ast = Ibex::Frontend::Parser.new(result.source, file: "mapped.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build

    assert_includes result.source, "bison_nt_expr:"
    assert_includes result.source, "bison_nt_compstmt"
    assert_includes result.source, "token BISON_T_KEYWORD_BEGIN"
    assert_includes result.source, "token BISON_T_KEYWORD_BEGIN_2"
    assert_includes result.source, "token BISON_T_IMPORT"
    assert_includes result.source, 'token OP "operator"'
    refute_includes result.source, "BISON_T_IGNORED"
    refute_includes result.source, "TOKEN_CODE"
    assert_operator automaton.states.length, :>, 0
  end

  def test_byte_rule_and_token_budgets_fail_explicitly
    assert_budget_phase("input_bytes", max_bytes: 1)
    assert_budget_phase("tokenization", max_tokens: 1)
    assert_budget_phase("rules", max_rules: 1, source: "%%\na: A;\nb: B;\n%%\n")
  end

  private

  def import(source)
    Ibex::BisonImport::Importer.new(source, file: "sample.y", class_name: "ImportedSample").run
  end

  def assert_budget_phase(phase, source: SOURCE, **limits)
    error = assert_raises(Ibex::BisonImport::BudgetExceeded) do
      Ibex::BisonImport::Importer.new(source, file: "budget.y", **limits).run
    end
    assert_equal phase, error.details.fetch(:phase)
  end
end
