# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLIGenerationStabilityTest < Minitest::Test
  def test_render_time_same_size_source_change_does_not_publish
    Dir.mktmpdir("ibex-cli-stability") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      File.binwrite(grammar, grammar_source("P"))
      File.binwrite(parser, "old parser")
      timestamp = File.mtime(grammar)
      errors = StringIO.new
      hook = lambda do
        File.binwrite(grammar, grammar_source("Q"))
        File.utime(timestamp, timestamp, grammar)
      end

      status = with_render_hook(hook) { run_cli(["-o", parser, grammar], stderr: errors) }

      assert_equal 1, status
      assert_match(/source changed/, errors.string)
      assert_equal "old parser", File.binread(parser)
    end
  end

  def test_render_time_lexical_root_symlink_retarget_does_not_publish
    Dir.mktmpdir("ibex-cli-stability") do |directory|
      first = File.join(directory, "first.y")
      second = File.join(directory, "second.y")
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      File.binwrite(first, grammar_source("P"))
      File.binwrite(second, grammar_source("Q"))
      File.symlink("first.y", grammar)
      File.binwrite(parser, "old parser")
      hook = lambda do
        File.unlink(grammar)
        File.symlink("second.y", grammar)
      end

      status = with_render_hook(hook) { run_cli(["-o", parser, grammar]) }

      assert_equal 1, status
      assert_equal "old parser", File.binread(parser)
      assert_equal "second.y", File.readlink(grammar)
    end
  end

  def test_render_created_output_symlink_cannot_replace_the_grammar
    Dir.mktmpdir("ibex-cli-stability") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      source = grammar_source("P")
      File.binwrite(grammar, source)
      errors = StringIO.new
      hook = -> { File.symlink(grammar, parser) }

      status = with_render_hook(hook) { run_cli(["-o", parser, grammar], stderr: errors) }

      assert_equal 1, status
      assert_match(/aliases generation input/, errors.string)
      assert_equal source, File.binread(grammar)
      assert File.symlink?(parser)
    end
  end

  def test_check_revalidates_inputs_after_all_file_comparisons
    Dir.mktmpdir("ibex-cli-stability") do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      File.binwrite(grammar, grammar_source("P"))
      assert_equal 0, run_cli(["-o", parser, grammar])
      original = File.method(:binread)
      changed = false
      reader = lambda do |path, *arguments|
        result = original.call(path, *arguments)
        if File.expand_path(path) == File.expand_path(parser) && !changed
          File.binwrite(grammar, grammar_source("Q"))
          changed = true
        end
        result
      end
      errors = StringIO.new

      status = File.stub(:binread, reader) do
        run_cli(["--check", "-o", parser, grammar], stderr: errors)
      end

      assert_equal 1, status
      assert_match(/source changed/, errors.string)
    end
  end

  private

  def grammar_source(class_name)
    "class #{class_name}\nrule\nstart: TOKEN\nend\n"
  end

  def run_cli(arguments, stderr: StringIO.new)
    Ibex::CLI.start(arguments, stdout: StringIO.new, stderr: stderr)
  end

  def with_render_hook(hook, &block)
    original = Ibex::Codegen::Ruby.method(:new)
    factory = lambda do |*arguments, **keywords|
      generator = original.call(*arguments, **keywords)
      proxy = Object.new
      proxy.define_singleton_method(:generate) do
        source = generator.generate
        hook.call
        source
      end
      proxy
    end
    Ibex::Codegen::Ruby.stub(:new, factory, &block)
  end
end
