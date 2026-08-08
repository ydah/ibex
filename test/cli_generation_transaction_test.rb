# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "stringio"
require "tmpdir"

class CLIGenerationTransactionTest < Minitest::Test
  def test_manifest_is_opt_in_and_default_path_is_beside_parser
    Dir.mktmpdir("ibex-cli-generation") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      manifest = File.join(directory, "parser.ibex.json")
      File.binwrite(grammar, grammar_source)

      assert_equal 0, run_cli(["-o", parser, grammar])
      refute File.exist?(manifest)
      assert_equal 0, run_cli(["--manifest", "-o", parser, grammar])

      document = Ibex::GenerationManifest.validate_file(manifest)
      assert_equal File.realpath(grammar), document.dig("input", "root")
      assert_equal(["parser"], document.fetch("artifacts").map { |entry| entry.fetch("kind") })
    end
  end

  def test_manifest_records_the_canonical_effective_cst_trivia_policy
    Dir.mktmpdir("ibex-cli-generation") do |directory|
      grammar = File.join(directory, "parser.y")
      File.binwrite(grammar, cst_grammar_source)
      cases = {
        "default" => [[], "leading"],
        "leading" => [["--cst-trivia=leading"], "leading"],
        "balanced" => [["--cst-trivia=balanced"], "balanced"],
        "drop" => [["--cst-trivia=drop"], "drop"],
        "attach" => [["--cst-trivia=attach"], "leading"]
      }

      documents = cases.to_h do |name, (arguments, expected)|
        document = generate_manifest(directory, grammar, name, arguments)
        assert_equal 1, document.fetch("schema_version")
        assert_equal expected, document.fetch("options").fetch("cst_trivia")
        [name, document]
      end

      assert_equal documents.fetch("default").fetch("options"), documents.fetch("leading").fetch("options")
      assert_equal documents.fetch("default").fetch("options"), documents.fetch("attach").fetch("options")
      refute_equal documents.fetch("leading").fetch("options"), documents.fetch("balanced").fetch("options")
      refute_equal documents.fetch("leading").fetch("options"), documents.fetch("drop").fetch("options")
    end
  end

  def test_manifest_distinguishes_source_owned_cst_trivia
    Dir.mktmpdir("ibex-cli-generation") do |directory|
      grammar = File.join(directory, "parser.y")
      File.binwrite(grammar, <<~GRAMMAR)
        class P
        pragma cst
        parser
          cst_trivia balanced
        end
        rule
        start: TOKEN
        end
      GRAMMAR
      document = generate_manifest(directory, grammar, "source-owned", [])
      options = document.fetch("options")
      entry = options.fetch("effective_configuration").find do |candidate|
        candidate.fetch("key") == "cst.trivia"
      end

      assert_equal "balanced", options.fetch("cst_trivia")
      assert_equal "balanced", entry.fetch("value")
      assert_equal "grammar", entry.dig("origin", "kind")
      assert_equal true, entry.fetch("canonical")
    end
  end

  def test_default_manifest_path_uses_lexical_parser_path_for_symlinked_root
    Dir.mktmpdir("ibex-cli-generation") do |directory|
      source_directory = File.join(directory, "source")
      invocation_directory = File.join(directory, "invocation")
      Dir.mkdir(source_directory)
      Dir.mkdir(invocation_directory)
      source = File.join(source_directory, "parser.y")
      grammar = File.join(invocation_directory, "parser.y")
      parser = File.join(invocation_directory, "parser.rb")
      manifest = File.join(invocation_directory, "parser.ibex.json")
      File.binwrite(source, grammar_source)
      File.symlink(source, grammar)

      assert_equal 0, run_cli(["--manifest", grammar])

      assert File.file?(parser)
      assert File.file?(manifest)
      refute File.exist?(File.join(source_directory, "parser.ibex.json"))
      assert_equal File.realpath(source), Ibex::GenerationManifest.validate_file(manifest).dig("input", "root")
    end
  end

  def test_check_verifies_an_explicit_manifest_without_rewriting
    Dir.mktmpdir("ibex-cli-generation") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      manifest = File.join(directory, "generation.json")
      File.binwrite(grammar, grammar_source)
      arguments = ["--manifest=#{manifest}", "-o", parser, grammar]
      assert_equal 0, run_cli(arguments)
      assert_equal 0, run_cli(["--check", *arguments])
      File.binwrite(manifest, "{}\n")

      errors = StringIO.new
      assert_equal 1, run_cli(["--check", *arguments], stderr: errors)
      assert_match(/generated generation manifest is stale/, errors.string)
      assert_equal "{}\n", File.binread(manifest)
    end
  end

  def test_include_cannot_be_overwritten_by_an_output_discovered_after_resolution
    Dir.mktmpdir("ibex-cli-generation") do |directory|
      grammar = File.join(directory, "root.y")
      fragment = File.join(directory, "fragment.y")
      original = "fragment\nrule\nhelper: TOKEN\nend\n"
      File.binwrite(grammar, "class P\ninclude \"fragment.y\"\nrule\nstart: helper\nend\n")
      File.binwrite(fragment, original)
      errors = StringIO.new

      assert_equal 1, run_cli(["--mode=extended", "-o", fragment, grammar], stderr: errors)
      assert_match(/paths must be distinct/, errors.string)
      assert_equal original, File.binread(fragment)
    end
  end

  def test_preflight_rejects_case_folded_output_collisions
    Dir.mktmpdir("ibex-cli-generation") do |directory|
      grammar = File.join(directory, "grammar.y")
      parser = File.join(directory, "Parser.rb")
      manifest = File.join(directory, "parser.rb")
      File.binwrite(grammar, grammar_source)
      errors = StringIO.new

      status = run_cli(["--manifest=#{manifest}", "-o", parser, grammar], stderr: errors)

      assert_equal 1, status
      assert_match(/paths must be distinct/, errors.string)
      refute File.exist?(parser)
      refute File.exist?(manifest)
    end
  end

  def test_render_failure_leaves_every_existing_output_unchanged
    Dir.mktmpdir("ibex-cli-generation") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      report = File.join(directory, "parser.output")
      railroad = File.join(directory, "parser.svg")
      messages = File.join(directory, "messages.json")
      File.binwrite(grammar, grammar_source)
      File.binwrite(parser, "old parser")
      File.binwrite(report, "old report")
      File.binwrite(railroad, "old railroad")
      File.binwrite(messages, "{")

      errors = StringIO.new
      status = run_cli(
        ["-v", "-O", report, "--railroad", railroad, "--messages", messages, "-o", parser, grammar],
        stderr: errors
      )

      assert_equal 1, status
      assert_equal "old parser", File.binread(parser)
      assert_equal "old report", File.binread(report)
      assert_equal "old railroad", File.binread(railroad)
    end
  end

  def test_status_messages_keep_the_legacy_registration_order
    Dir.mktmpdir("ibex-cli-generation") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      File.binwrite(grammar, "class P\nrule\nstart: TOKEN { result = val[0] }\nend\n")
      errors = StringIO.new

      assert_equal 0, run_cli(
        ["-S", "-v", "--rbs", "--action-source", "--manifest", "-o", parser, grammar],
        stderr: errors
      )

      writes = errors.string.lines.grep(/ibex: wrote/).map(&:strip)
      assert_equal [
        "ibex: wrote #{File.join(directory, 'parser.output')}",
        "ibex: wrote #{File.join(directory, 'parser.actions.rb')}",
        "ibex: wrote #{parser}",
        "ibex: wrote #{File.join(directory, 'parser.rbs')}",
        "ibex: wrote #{File.join(directory, 'parser.ibex.json')}"
      ], writes
    end
  end

  private

  def grammar_source
    "class P\nrule\nstart: TOKEN\nend\n"
  end

  def cst_grammar_source
    "class P\npragma cst\nrule\nstart: TOKEN\nend\n"
  end

  def generate_manifest(directory, grammar, name, arguments)
    parser = File.join(directory, "#{name}.rb")
    manifest = File.join(directory, "#{name}.json")
    assert_equal 0, run_cli([*arguments, "--manifest=#{manifest}", "-o", parser, grammar])
    Ibex::GenerationManifest.validate_file(manifest)
  end

  def run_cli(arguments, stderr: StringIO.new)
    Ibex::CLI.start(arguments, stdout: StringIO.new, stderr: stderr)
  end
end
