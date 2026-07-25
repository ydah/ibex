# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLIActionSourceTest < Minitest::Test
  def test_opt_in_writes_default_or_explicit_shadow_without_changing_parser_or_executing_user_code
    Dir.mktmpdir("ibex-action-source") do |directory|
      grammar = File.join(directory, "grammar.y")
      marker = File.join(directory, "executed")
      baseline = File.join(directory, "baseline.rb")
      parser = File.join(directory, "parser.rb")
      explicit = File.join(directory, "static", "semantic.rb")
      Dir.mkdir(File.dirname(explicit))
      File.write(grammar, dangerous_grammar(marker))

      assert_equal 0, run_cli(["-o", baseline, grammar])
      assert_equal 0, run_cli(["--action-source", "-o", parser, grammar])
      assert_equal File.binread(baseline), File.binread(parser)
      default_shadow = File.join(directory, "parser.actions.rb")
      assert File.exist?(default_shadow)
      refute File.exist?(marker)
      refute_includes File.read(default_shadow), "HEADER_MARKER"
      refute_includes File.read(default_shadow), "INNER_MARKER"
      refute_includes File.read(default_shadow), "FOOTER_MARKER"

      assert_equal 0, run_cli(["--action-source=#{explicit}", "-o", parser, grammar])
      assert_equal File.binread(default_shadow), File.binread(explicit)
      refute File.exist?(marker)
    end
  end

  def test_check_verifies_missing_and_stale_action_source_without_rewriting
    Dir.mktmpdir("ibex-action-check") do |directory|
      grammar = File.join(directory, "grammar.y")
      parser = File.join(directory, "parser.rb")
      shadow = File.join(directory, "parser.actions.rb")
      File.write(grammar, "class P\nrule\nstart: TOKEN { result = val[0] }\nend\n")

      assert_equal 0, run_cli(["--action-source", "-o", parser, grammar])
      assert_equal 0, run_cli(["--check", "--action-source", "-o", parser, grammar])

      File.write(shadow, "# stale\n")
      errors = StringIO.new
      assert_equal 1, run_cli(["--check", "--action-source", "-o", parser, grammar], stderr: errors)
      assert_match(/generated action source is stale/, errors.string)
      assert_equal "# stale\n", File.read(shadow)

      File.delete(shadow)
      errors = StringIO.new
      assert_equal 1, run_cli(["--check", "--action-source", "-o", parser, grammar], stderr: errors)
      assert_match(/generated action source is missing/, errors.string)
      refute File.exist?(shadow)
    end
  end

  def test_shadow_is_deterministic_when_resuming_from_grammar_ir
    Dir.mktmpdir("ibex-action-ir") do |directory|
      grammar = File.join(directory, "grammar.y")
      grammar_ir = File.join(directory, "grammar.json")
      direct_parser = File.join(directory, "direct.rb")
      resumed_parser = File.join(directory, "resumed.rb")
      direct_shadow = File.join(directory, "direct.actions.rb")
      resumed_shadow = File.join(directory, "resumed.actions.rb")
      File.write(grammar, inline_grammar)
      output = StringIO.new
      assert_equal 0, Ibex::CLI.start(
        ["--mode=extended", "--emit=grammar-ir", grammar], stdout: output, stderr: StringIO.new
      )
      File.write(grammar_ir, output.string)

      assert_equal 0, run_cli(
        ["--mode=extended", "--rbs", "--action-source=#{direct_shadow}", "-o", direct_parser, grammar]
      )
      assert_equal 0, run_cli(
        ["--from=grammar-ir", "--rbs", "--action-source=#{resumed_shadow}", "-o", resumed_parser, grammar_ir]
      )
      assert_equal File.binread(direct_shadow), File.binread(resumed_shadow)
      assert_equal File.binread(direct_parser.sub(/\.rb\z/, ".rbs")),
                   File.binread(resumed_parser.sub(/\.rb\z/, ".rbs"))
    end
  end

  def test_default_shadow_stays_beside_an_extensionless_parser_in_a_dotted_directory
    Dir.mktmpdir("ibex-action-extensionless") do |directory|
      output_directory = File.join(directory, "generated.v1")
      Dir.mkdir(output_directory)
      grammar = File.join(directory, "grammar.y")
      parser = File.join(output_directory, "parser")
      shadow = File.join(output_directory, "parser.actions.rb")
      signature = File.join(output_directory, "parser.rbs")
      File.write(grammar, "class P\nrule\nstart: TOKEN { result = val[0] }\nend\n")

      assert_equal 0, run_cli(["--rbs", "--action-source", "-o", parser, grammar])
      assert File.exist?(parser)
      assert File.exist?(shadow)
      assert File.exist?(signature)
      refute File.exist?(File.join(directory, "generated.actions.rb"))
    end
  end

  def test_rejects_canonical_collisions_before_writing_any_output
    Dir.mktmpdir("ibex-action-collision") do |directory|
      grammar = File.join(directory, "grammar.y")
      parser = File.join(directory, "parser.rb")
      shared = File.join(directory, "shared")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")

      action_collision_cases(grammar, parser, shared).each do |arguments|
        errors = StringIO.new
        assert_equal 1, run_cli([*arguments, grammar], stderr: errors), arguments.inspect
        assert_match(/paths must be distinct/, errors.string)
      end
      refute File.exist?(parser)
      refute File.exist?(shared)
      assert_alias_collisions(directory, grammar, parser)
    end
  end

  def test_rejects_non_ruby_and_check_only_modes
    Dir.mktmpdir("ibex-action-mode") do |directory|
      grammar = File.join(directory, "grammar.y")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")

      errors = StringIO.new
      assert_equal 1, run_cli(["--emit=sets", "--action-source", grammar], stderr: errors)
      assert_match(/--action-source requires --emit=ruby/, errors.string)

      errors = StringIO.new
      assert_equal 1, run_cli(["--check-only", "--action-source", grammar], stderr: errors)
      assert_match(/cannot be combined/, errors.string)
    end
  end

  private

  def run_cli(arguments, stderr: StringIO.new)
    Ibex::CLI.start(arguments, stdout: StringIO.new, stderr: stderr)
  end

  def dangerous_grammar(marker)
    <<~GRAMMAR
      class P
      rule
      start: TOKEN { File.write(#{marker.inspect}, "ACTION_MARKER"); result = val[0] }
      end
      ---- header
      File.write(#{marker.inspect}, "HEADER_MARKER")
      ---- inner
      File.write(#{marker.inspect}, "INNER_MARKER")
      ---- footer
      File.write(#{marker.inspect}, "FOOTER_MARKER")
    GRAMMAR
  end

  def inline_grammar
    <<~GRAMMAR
      class P
      pragma extended
      type TOKEN "Integer"
      type helper "Integer"
      type start "String"
      rule
      %inline helper: TOKEN { result = val[0] }
      start: helper { result = val[0].to_s }
      end
    GRAMMAR
  end

  def action_collision_cases(grammar, parser, shared)
    [
      ["--action-source=#{grammar}", "-o", parser],
      ["--action-source=#{parser}", "-o", parser],
      ["--rbs=#{shared}", "--action-source=#{shared}", "-o", parser],
      ["--dot=#{shared}", "--action-source=#{shared}", "-o", parser],
      ["--mermaid=#{shared}", "--action-source=#{shared}", "-o", parser],
      ["--html=#{shared}", "--action-source=#{shared}", "-o", parser],
      ["--railroad=#{shared}", "--action-source=#{shared}", "-o", parser],
      ["-v", "-O", shared, "--action-source=#{shared}", "-o", parser]
    ]
  end

  def assert_alias_collisions(directory, grammar, parser)
    alias_directory = File.join(directory, "alias")
    File.symlink(directory, alias_directory)
    errors = StringIO.new
    assert_equal 1, run_cli(
      ["--action-source=#{File.join(alias_directory, 'parser.rb')}", "-o", parser, grammar], stderr: errors
    )
    assert_match(/paths must be distinct/, errors.string)

    dangling_alias = File.join(directory, "dangling.rb")
    File.symlink(File.basename(parser), dangling_alias)
    errors = StringIO.new
    assert_equal 1, run_cli(
      ["--action-source=#{dangling_alias}", "-o", parser, grammar], stderr: errors
    )
    assert_match(/paths must be distinct/, errors.string)
    refute File.exist?(parser)
  end
end
