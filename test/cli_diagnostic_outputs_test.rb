# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tempfile"

class CLIDiagnosticOutputsTest < Minitest::Test
  def test_emits_deterministic_nullable_first_and_follow_sets
    with_grammar(<<~GRAMMAR) do |grammar|
      class P
      rule
      start: optional 'b'
      optional: 'a' |
      end
    GRAMMAR
      first = capture_cli(["--emit=sets", grammar.path])
      second = capture_cli(["--emit=sets", grammar.path])
      assert_equal first, second
      Tempfile.create(["grammar-ir", ".json"]) do |grammar_ir|
        grammar_ir.write(capture_cli(["--emit=grammar-ir", grammar.path]))
        grammar_ir.flush
        assert_equal first, capture_cli(["--from=grammar-ir", "--emit=sets", grammar_ir.path])
      end
      assert_equal(
        {
          "nullable" => ["optional"],
          "first" => { "optional" => ["'a'"], "start" => ["'a'", "'b'"] },
          "follow" => { "optional" => ["'b'"], "start" => ["$eof"] }
        },
        JSON.parse(first)
      )
    end
  end

  def test_warning_output_names_unused_precedence_and_unreachable_terminals
    with_grammar(<<~GRAMMAR) do |grammar|
      class P
      token LIVE DEAD
      preclow
      left UNUSED
      prechigh
      rule
      start: LIVE
      dead: DEAD
      end
    GRAMMAR
      warnings = StringIO.new
      assert_equal 0, Ibex::CLI.start(["-C", "--warnings=all", grammar.path],
                                      stdout: StringIO.new, stderr: warnings)
      assert_includes warnings.string, "warning: unused precedence UNUSED"
      assert_includes warnings.string, "warning: declared terminal DEAD is unreachable"
    end
  end

  def test_writes_dot_mermaid_and_html_side_outputs
    with_grammar("class P\nrule\nstart: TOKEN\nend\n") do |grammar|
      Tempfile.create(["automaton", ".dot"]) do |dot|
        Tempfile.create(["automaton", ".mmd"]) do |mermaid|
          Tempfile.create(["automaton", ".html"]) do |html|
            Tempfile.create(["parser", ".rb"]) do |parser|
              run_cli(["--dot", dot.path, "--mermaid", mermaid.path, "--html", html.path,
                       "-o", parser.path, grammar.path])
              assert_includes File.read(dot.path), "digraph"
              assert_includes File.read(mermaid.path), "flowchart LR"
              assert_includes File.read(html.path), "<!doctype html>"
            end
          end
        end
      end
    end
  end

  def test_suggests_ielr_only_when_it_avoids_unexpected_lalr_conflicts
    with_grammar(<<~GRAMMAR) do |grammar|
      class P
      rule
      start: 'a' first 'd'
           | 'b' first 'e'
           | 'a' second 'e'
           | 'b' second 'd'
      first: 'c'
      second: 'c'
      end
    GRAMMAR
      default_errors = StringIO.new
      default_status = Ibex::CLI.start(["--emit=automaton-ir", grammar.path],
                                       stdout: StringIO.new, stderr: default_errors)
      assert_equal 0, default_status
      assert_match(%r{note: --algorithm=ielr avoids \d+ reduce/reduce conflicts?}, default_errors.string)

      ielr_errors = StringIO.new
      ielr_status = Ibex::CLI.start(["--algorithm=ielr", "--emit=automaton-ir", grammar.path],
                                    stdout: StringIO.new, stderr: ielr_errors)
      assert_equal 0, ielr_status
      refute_match(/note: --algorithm=ielr avoids/, ielr_errors.string)
    end
  end

  def test_does_not_suggest_ielr_for_an_expected_lalr_conflict
    with_grammar("class P\nexpect 1\nrule\nstart: start start | TOKEN\nend\n") do |grammar|
      errors = StringIO.new
      status = Ibex::CLI.start(["--emit=automaton-ir", grammar.path],
                               stdout: StringIO.new, stderr: errors)

      assert_equal 0, status
      refute_match(/note: --algorithm=ielr avoids/, errors.string)
    end
  end

  private

  def with_grammar(source)
    Tempfile.create(["grammar", ".y"]) do |grammar|
      grammar.write(source)
      grammar.flush
      yield grammar
    end
  end

  def capture_cli(arguments)
    output = StringIO.new
    errors = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: output, stderr: errors)
    assert_equal 0, status, errors.string
    output.string
  end

  def run_cli(arguments)
    errors = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: StringIO.new, stderr: errors)
    assert_equal 0, status, errors.string
  end
end
