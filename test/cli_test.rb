# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "open3"
require "rbconfig"
require "tempfile"
require "tmpdir"

# rubocop:disable Metrics/ClassLength -- CLI integration cases share the same process-level harness.
class CLITest < Minitest::Test
  def test_version
    output = StringIO.new
    assert_equal 0, Ibex::CLI.start(["--version"], stdout: output, stderr: StringIO.new)
    assert_equal "ibex #{Ibex::VERSION}\n", output.string
  end

  def test_emits_grammar_ir
    Tempfile.create(["grammar", ".y"]) do |file|
      file.write("class P\nrule\nstart: TOKEN\nend\n")
      file.flush
      output = StringIO.new
      status = Ibex::CLI.start(["--emit=grammar-ir", file.path], stdout: output, stderr: StringIO.new)
      assert_equal 0, status
      assert_equal "grammar", JSON.parse(output.string).fetch("ibex_ir")
    end
  end

  def test_emits_independently_versioned_lexer_ir
    path = File.expand_path("fixtures/grammar/lexer.y", __dir__)
    output = StringIO.new
    status = Ibex::CLI.start(
      ["--mode=extended", "--emit=lexer-ir", path], stdout: output, stderr: StringIO.new
    )
    document = JSON.parse(output.string)

    assert_equal 0, status
    assert_equal "lexer", document.fetch("ibex_ir")
    assert_equal 1, document.fetch("schema_version")
  end

  def test_rejects_lexer_ir_output_without_a_lexer_declaration
    Tempfile.create(["grammar", ".y"]) do |file|
      file.write("class P\nrule\nstart: TOKEN\nend\n")
      file.flush
      errors = StringIO.new

      assert_equal 1, Ibex::CLI.start(["--emit=lexer-ir", file.path], stdout: StringIO.new, stderr: errors)
      assert_includes errors.string, "grammar does not declare a lexer"
    end
  end

  def test_emits_automaton_ir
    Tempfile.create(["grammar", ".y"]) do |file|
      file.write("class P\nrule\nstart: TOKEN\nend\n")
      file.flush
      output = StringIO.new
      status = Ibex::CLI.start(["--emit=automaton-ir", file.path], stdout: output, stderr: StringIO.new)
      assert_equal 0, status
      assert_equal "automaton", JSON.parse(output.string).fetch("ibex_ir")
    end
  end

  def test_emits_ielr_automaton_ir
    Tempfile.create(["grammar", ".y"]) do |file|
      file.write("class P\nrule\nstart: TOKEN\nend\n")
      file.flush
      output = StringIO.new
      status = Ibex::CLI.start(
        ["--algorithm=ielr", "--emit=automaton-ir", file.path],
        stdout: output,
        stderr: StringIO.new
      )

      assert_equal 0, status
      assert_equal "ielr1", JSON.parse(output.string).fetch("algorithm")
    end
  end

  def test_entry_isolation_emits_independent_entry_state_sets
    Tempfile.create(["multiple-start", ".y"]) do |file|
      file.write(<<~GRAMMAR)
        class P
        pragma extended
        start program expression
        rule
        program: A B
        expression: A
        end
      GRAMMAR
      file.flush
      output = StringIO.new
      status = Ibex::CLI.start(
        ["--entry-isolation", "--emit=automaton-ir", file.path],
        stdout: output,
        stderr: StringIO.new
      )
      document = JSON.parse(output.string)

      assert_equal 0, status
      assert_operator document.fetch("entry_states").fetch("expression"), :>,
                      document.fetch("entry_states").fetch("program")
    end
  end

  def test_generates_ruby_file
    Tempfile.create(["grammar", ".y"]) do |grammar|
      Tempfile.create(["parser", ".rb"]) do |output|
        grammar.write("class P\nrule\nstart: TOKEN\nend\n")
        grammar.flush
        status = Ibex::CLI.start(["--table=plain", "-o", output.path, grammar.path],
                                 stdout: StringIO.new, stderr: StringIO.new)
        assert_equal 0, status
        assert_includes File.read(output.path), "class P < Ibex::Runtime::Parser"
      end
    end
  end

  def test_generates_each_documented_cst_trivia_policy
    Dir.mktmpdir("ibex-cst-trivia") do |directory|
      grammar = File.join(directory, "grammar.y")
      File.binwrite(grammar, <<~GRAMMAR)
        class CSTPolicyParser
        pragma cst
        token VALUE
        lexer
          skip /[[:space:]]+/
          VALUE /[0-9]+/
        end
        rule
        start: VALUE
        end
      GRAMMAR

      { leading: :leading, balanced: :balanced, drop: :drop, attach: :leading }.each do |option, expected|
        output = File.join(directory, "#{option}.rb")
        run_cli(["--cst-trivia=#{option}", "--output-file=#{output}", grammar])
        assert_includes File.binread(output), ":trivia_policy => :#{expected}"
      end
    end
  end

  def test_generates_rbs_beside_the_parser
    Dir.mktmpdir("ibex-rbs") do |directory|
      grammar = File.join(directory, "grammar.y")
      parser = File.join(directory, "generated.rb")
      File.write(grammar, "class API::Generated\nrule\nstart: TOKEN\nend\n")
      run_cli(["--rbs", "-o", parser, grammar])

      signature = File.read(File.join(directory, "generated.rbs"))
      assert_includes signature, "module API"
      assert_includes signature, "class Generated < Ibex::Runtime::Parser"
    end
  end

  def test_ast_and_check_only_status_options
    with_grammar do |grammar|
      ast_output = StringIO.new
      assert_equal 0, Ibex::CLI.start(["--emit=ast", grammar.path], stdout: ast_output, stderr: StringIO.new)
      assert_equal "Root", JSON.parse(ast_output.string).fetch("node")

      status_output = StringIO.new
      assert_equal 0, Ibex::CLI.start(["-C", "-S", grammar.path], stdout: StringIO.new, stderr: status_output)
      assert_includes status_output.string, "reading"
    end
  end

  def test_warning_levels_show_or_promote_structured_diagnostics
    Tempfile.create(["warnings", ".y"]) do |grammar|
      grammar.write("class P\ntoken USED UNUSED\nrule\nstart: USED\nend\n")
      grammar.flush

      absent = StringIO.new
      assert_equal 0, Ibex::CLI.start(["-C", grammar.path], stdout: StringIO.new, stderr: absent)
      assert_empty absent.string

      visible = StringIO.new
      assert_equal 0, Ibex::CLI.start(["-C", "--warnings=all", grammar.path],
                                      stdout: StringIO.new, stderr: visible)
      assert_match(/:2:1: warning: unused terminal UNUSED/, visible.string)

      promoted = StringIO.new
      assert_equal 1, Ibex::CLI.start(["-C", "--warnings=error", grammar.path],
                                      stdout: StringIO.new, stderr: promoted)
      assert_match(/:2:1: warning treated as error: unused terminal UNUSED/, promoted.string)
    end
  end

  def test_strict_warnings_promote_risky_lexer_patterns
    Tempfile.create(["lexer-warning", ".y"]) do |grammar|
      grammar.write(<<~GRAMMAR)
        class P
        pragma extended
        token WORD
        lexer
          WORD /(a+)+/
        end
        rule
        start: WORD
        end
      GRAMMAR
      grammar.flush
      errors = StringIO.new
      status = Ibex::CLI.start(
        ["-C", "--warnings=all,error", grammar.path], stdout: StringIO.new, stderr: errors
      )

      assert_equal 1, status
      message = "warning treated as error: lexer pattern for WORD may exhibit excessive backtracking"
      assert_includes errors.string, message
    end
  end

  def test_strict_warnings_detect_an_empty_language
    Tempfile.create(["empty-language", ".y"]) do |grammar|
      grammar.write("class P\nrule\nstart: loop\nloop: start\nend\n")
      grammar.flush
      errors = StringIO.new
      status = Ibex::CLI.start(["-C", "--warnings=error", grammar.path], stdout: StringIO.new, stderr: errors)
      assert_equal 1, status
      assert_includes errors.string, "start symbol start derives no terminal sentence"
    end
  end

  def test_strict_warnings_honor_shift_reduce_and_reduce_reduce_expectations
    Tempfile.create(["expected-conflicts", ".y"]) do |grammar|
      source = <<~GRAMMAR
        class P
        pragma extended
        expect 0
        %expect-rr 1
        rule
        start: first | second
        first: TOKEN
        second: TOKEN
        end
      GRAMMAR
      grammar.write(source)
      grammar.flush
      assert_equal 0, Ibex::CLI.start(
        ["-C", "--warnings=error", grammar.path], stdout: StringIO.new, stderr: StringIO.new
      )

      grammar.rewind
      grammar.truncate(0)
      grammar.write(source.sub("%expect-rr 1", "%expect-rr 0"))
      grammar.flush
      errors = StringIO.new
      assert_equal 1, Ibex::CLI.start(
        ["-C", "--warnings=error", grammar.path], stdout: StringIO.new, stderr: errors
      )
      assert_includes errors.string, "reduce/reduce conflicts; expected 0; conflict treated as error"
    end
  end

  def test_report_executable_and_superclass_options
    with_grammar do |grammar|
      Tempfile.create(["report", ".output"]) do |report|
        Tempfile.create(["parser", ".rb"]) do |output|
          arguments = ["-v", "-O", report.path, "-e", "/usr/bin/env ruby", "--superclass=Ibex::Runtime::Parser",
                       "-o", output.path, grammar.path]
          assert_equal 0, Ibex::CLI.start(arguments, stdout: StringIO.new, stderr: StringIO.new)
          assert_includes File.read(report.path), "State 0"
          assert File.executable?(output.path)
          assert File.read(output.path).start_with?("#!/usr/bin/env ruby\n")
        end
      end
    end
  end

  def test_line_convert_all_maps_footer_to_the_grammar_file
    Tempfile.create(["line-convert-all", ".y"]) do |grammar|
      Tempfile.create(["line-convert-all-parser", ".rb"]) do |output|
        grammar.write("class P\nrule\nstart:\nend\n---- footer\nraise 'footer'\n")
        grammar.flush
        run_cli(["--line-convert-all", "-o", output.path, grammar.path])

        _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I#{File.expand_path('../lib', __dir__)}", output.path)
        refute status.success?
        assert_includes stderr, "#{grammar.path}:6"
      end
    end
  end

  def test_help_lists_compatible_options
    output = StringIO.new
    assert_equal 0, Ibex::CLI.start(["--help"], stdout: output, stderr: StringIO.new)
    compatible = %w[
      --output-file --debug --verbose --embedded --rbs --action-source --entry-isolation
      --check --check-only --superclass
    ]
    compatible.each do |option|
      assert_includes output.string, option
    end
  end

  def test_ir_stages_generate_identical_ruby
    with_grammar do |grammar|
      Tempfile.create(["grammar", ".json"]) do |grammar_ir|
        Tempfile.create(["automaton", ".json"]) do |automaton_ir|
          outputs = Array.new(3) { Tempfile.new(["parser", ".rb"]) }
          begin
            run_cli(["-o", outputs[0].path, grammar.path])
            grammar_json = capture_cli(["--emit=grammar-ir", grammar.path])
            File.write(grammar_ir.path, grammar_json)
            run_cli(["--from=grammar-ir", "-o", outputs[1].path, grammar_ir.path])
            automaton_json = capture_cli(["--from=grammar-ir", "--emit=automaton-ir", grammar_ir.path])
            File.write(automaton_ir.path, automaton_json)
            run_cli(["--from=automaton-ir", "-o", outputs[2].path, automaton_ir.path])
            generated = outputs.map { |output| File.read(output.path) }
            assert_equal generated[0], generated[1]
            assert_equal generated[0], generated[2]
          ensure
            outputs.each(&:close!)
          end
        end
      end
    end
  end

  def test_line_convert_all_is_stable_when_resuming_from_grammar_ir
    Dir.mktmpdir("ibex-line-convert-ir") do |directory|
      grammar = File.join(directory, "grammar.y")
      grammar_ir = File.join(directory, "grammar.json")
      direct = File.join(directory, "direct.rb")
      resumed = File.join(directory, "resumed.rb")
      File.write(grammar, <<~GRAMMAR)
        class P
        rule
        start: TOKEN
        end
        ---- inner
        def marker = :inner
        ---- footer
        FOOTER_MARKER = true
      GRAMMAR

      File.write(grammar_ir, capture_cli(["--emit=grammar-ir", grammar]))
      run_cli(["--line-convert-all", "-o", direct, grammar])
      run_cli(["--line-convert-all", "--from=grammar-ir", "-o", resumed, grammar_ir])

      assert_equal File.read(direct), File.read(resumed)
    end
  end

  def test_reports_cli_errors
    errors = StringIO.new
    assert_equal 1, Ibex::CLI.start([], stdout: StringIO.new, stderr: errors)
    assert_equal "(cli):1:1: grammar file is required\n", errors.string
  end

  private

  def with_grammar
    Tempfile.create(["grammar", ".y"]) do |grammar|
      grammar.write("class P\nrule\nstart: TOKEN\nend\n")
      grammar.flush
      yield grammar
    end
  end

  def run_cli(arguments)
    errors = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: StringIO.new, stderr: errors)
    assert_equal 0, status, errors.string
  end

  def capture_cli(arguments)
    output = StringIO.new
    errors = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: output, stderr: errors)
    assert_equal 0, status, errors.string
    output.string
  end
end
# rubocop:enable Metrics/ClassLength
