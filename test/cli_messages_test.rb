# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLIMessagesTest < Minitest::Test
  def test_errors_update_uses_default_path_preserves_messages_and_archives_disappeared_states
    Dir.mktmpdir("ibex-messages") do |directory|
      grammar = File.join(directory, "grammar.y")
      messages = File.join(directory, "grammar.messages")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")
      File.write(messages, <<~MESSAGES)
        # ibex-messages v1
        state 0
        | Keep this custom message.
        end
        state 999
        | Preserve this removed message.
        end
      MESSAGES

      run_cli(["errors", "--update", grammar])

      rendered = File.read(messages)
      assert_includes rendered, "state 0"
      assert_includes rendered, "| Keep this custom message."
      assert_includes rendered, "removed 999"
      assert_includes rendered, "| Preserve this removed message."

      run_cli(["errors", "--update", grammar])
      assert_equal rendered, File.read(messages)
    end
  end

  def test_errors_update_is_identical_for_source_grammar_ir_and_automaton_ir
    Dir.mktmpdir("ibex-messages-ir") do |directory|
      grammar = File.join(directory, "grammar.y")
      grammar_ir = File.join(directory, "grammar.json")
      automaton_ir = File.join(directory, "automaton.json")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")
      File.write(grammar_ir, capture_cli(["--emit=grammar-ir", grammar]))
      File.write(automaton_ir, capture_cli(["--emit=automaton-ir", grammar]))

      outputs = [File.join(directory, "source.messages"), File.join(directory, "grammar-ir.messages"),
                 File.join(directory, "automaton-ir.messages")]
      run_cli(["errors", "--update=#{outputs[0]}", grammar])
      run_cli(["errors", "--from=grammar-ir", "--update=#{outputs[1]}", grammar_ir])
      run_cli(["errors", "--from=automaton-ir", "--update=#{outputs[2]}", automaton_ir])

      assert_equal File.read(outputs[0]), File.read(outputs[1])
      assert_equal File.read(outputs[0]), File.read(outputs[2])
    end
  end

  def test_messages_option_embeds_custom_message_and_rejects_unknown_state
    Dir.mktmpdir("ibex-messages-generate") do |directory|
      grammar = File.join(directory, "grammar.y")
      messages = File.join(directory, "grammar.messages")
      generated = File.join(directory, "parser.rb")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")
      File.write(messages, "# ibex-messages v1\nstate 0\n| Expected a token.\nend\n")

      run_cli(["--messages=#{messages}", "-o", generated, grammar])
      assert_includes File.read(generated), "Expected a token."

      File.write(messages, "# ibex-messages v1\nstate 999\n| stale\nend\n")
      errors = StringIO.new
      status = Ibex::CLI.start(["--messages=#{messages}", "-o", generated, grammar],
                               stdout: StringIO.new, stderr: errors)
      assert_equal 1, status
      assert_equal(
        "#{messages}:2:1: unknown error state 999 for current automaton; run `ibex errors --update`\n",
        errors.string
      )
    end
  end

  def test_messages_generation_is_identical_for_source_grammar_ir_and_automaton_ir
    Dir.mktmpdir("ibex-messages-generation-ir") do |directory|
      grammar = File.join(directory, "grammar.y")
      grammar_ir = File.join(directory, "grammar.json")
      automaton_ir = File.join(directory, "automaton.json")
      messages = File.join(directory, "grammar.messages")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")
      File.write(grammar_ir, capture_cli(["--emit=grammar-ir", grammar]))
      File.write(automaton_ir, capture_cli(["--emit=automaton-ir", grammar]))
      File.write(messages, "# ibex-messages v1\nstate 0\n| Expected a token.\nend\n")

      outputs = Array.new(3) { |index| File.join(directory, "parser-#{index}.rb") }
      run_cli(["--messages=#{messages}", "-o", outputs[0], grammar])
      run_cli(["--messages=#{messages}", "--from=grammar-ir", "-o", outputs[1], grammar_ir])
      run_cli(["--messages=#{messages}", "--from=automaton-ir", "-o", outputs[2], automaton_ir])

      assert_equal File.read(outputs[0]), File.read(outputs[1])
      assert_equal File.read(outputs[0]), File.read(outputs[2])
    end
  end

  def test_errors_subcommand_requires_update_without_changing_normal_option_parsing
    errors = StringIO.new
    status = Ibex::CLI.start(["errors", "grammar.y"], stdout: StringIO.new, stderr: errors)
    assert_equal 1, status
    assert_equal "(cli):1:1: errors command requires --update[=FILE]\n", errors.string

    Dir.mktmpdir("ibex-normal-cli") do |directory|
      grammar = File.join(directory, "grammar.y")
      output = File.join(directory, "parser.rb")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")
      run_cli(["--table=plain", "-o", output, grammar])
      assert File.exist?(output)
    end
  end

  def test_messages_option_is_limited_to_ruby_generation
    errors = StringIO.new
    status = Ibex::CLI.start(
      ["--emit=sets", "--messages=grammar.messages", "grammar.y"],
      stdout: StringIO.new,
      stderr: errors
    )
    assert_equal 1, status
    assert_equal "(cli):1:1: --messages is available only with --emit=ruby\n", errors.string

    errors = StringIO.new
    status = Ibex::CLI.start(
      ["--check-only", "--messages=grammar.messages", "grammar.y"],
      stdout: StringIO.new,
      stderr: errors
    )
    assert_equal 1, status
    assert_equal "(cli):1:1: --messages cannot be combined with --check-only\n", errors.string
  end

  def test_errors_help_does_not_require_an_input
    output = StringIO.new
    errors = StringIO.new
    status = Ibex::CLI.start(["errors", "--help"], stdout: output, stderr: errors)

    assert_equal 0, status
    assert_empty errors.string
    assert_includes output.string, "Usage: ibex errors --update[=FILE]"
  end

  def test_generation_rejects_paths_that_would_overwrite_messages
    Dir.mktmpdir("ibex-messages-paths") do |directory|
      grammar = File.join(directory, "grammar.y")
      messages = File.join(directory, "grammar.messages")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")
      original = "# ibex-messages v1\nstate 0\n| Keep me.\nend\n"
      File.write(messages, original)
      errors = StringIO.new

      status = Ibex::CLI.start(["--messages=#{messages}", "-o", messages, grammar],
                               stdout: StringIO.new, stderr: errors)
      assert_equal 1, status
      assert_match(/paths must be distinct/, errors.string)
      assert_equal original, File.read(messages)
    end
  end

  def test_errors_update_rejects_input_overwrite_and_invalid_ir_cleanly
    Dir.mktmpdir("ibex-messages-safe-update") do |directory|
      grammar = File.join(directory, "grammar.y")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")
      errors = StringIO.new
      status = Ibex::CLI.start(["errors", "--update=#{grammar}", grammar],
                               stdout: StringIO.new, stderr: errors)
      assert_equal 1, status
      assert_match(/must differ from the input path/, errors.string)
      assert File.read(grammar).start_with?("class P")

      broken = File.join(directory, "broken.json")
      File.write(broken, '{"ibex_ir":"grammar","schema_version":1}')
      errors = StringIO.new
      status = Ibex::CLI.start(["errors", "--from=grammar-ir", "--update", broken],
                               stdout: StringIO.new, stderr: errors)
      assert_equal 1, status
      assert_match(/\(ir\):1:1:/, errors.string)
    end
  end

  def test_errors_update_rejects_an_input_alias_and_preserves_existing_permissions
    Dir.mktmpdir("ibex-messages-safe-alias") do |directory|
      source = File.join(directory, "source.y")
      alias_path = File.join(directory, "grammar.y")
      messages = File.join(directory, "grammar.messages")
      original = "class P\nrule\nstart: TOKEN\nend\n"
      File.write(source, original)
      File.symlink(source, alias_path)

      errors = StringIO.new
      status = Ibex::CLI.start(["errors", "--update=#{source}", alias_path],
                               stdout: StringIO.new, stderr: errors)
      assert_equal 1, status
      assert_match(/must differ from the input path/, errors.string)
      assert_equal original, File.read(source)

      File.write(messages, "# ibex-messages v1\nstate 0\n| Keep me.\nend\n")
      File.chmod(0o644, messages)
      run_cli(["errors", "--update=#{messages}", source])
      assert_equal 0o644, File.stat(messages).mode & 0o777
    end
  end

  private

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
