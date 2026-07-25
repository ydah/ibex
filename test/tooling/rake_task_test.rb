# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/rake_task"
require "rake"
require "tmpdir"

class RakeTaskTest < Minitest::Test
  def setup
    @previous_rake_application = Rake.application
    Rake.application = Rake::Application.new
  end

  def teardown
    Rake.application = @previous_rake_application
  end

  def test_defines_a_file_task_that_generates_the_parser
    Dir.mktmpdir do |directory|
      grammar = File.join(directory, "calculator.y")
      output = File.join(directory, "calculator.rb")
      File.write(grammar, "class Calculator\nrule\nstart: TOKEN\nend\n")

      Ibex::RakeTask.new(output) do |task|
        task.grammar = grammar
        task.options = ["--mode=racc"]
      end

      task = Rake::Task[output]
      assert_equal [grammar], task.prerequisites
      task.invoke
      assert File.exist?(output)
      assert_includes File.read(output), "class Calculator"
    end
  end

  def test_infers_output_and_exposes_a_named_aggregate_task
    Dir.mktmpdir do |directory|
      grammar = File.join(directory, "parser.y")
      File.write(grammar, "class Parser\nrule\nstart: TOKEN\nend\n")

      Ibex::RakeTask.new(:generate_parser) { |task| task.grammar = grammar }

      output = File.join(directory, "parser.rb")
      assert Rake::Task.task_defined?(:generate_parser)
      assert_equal [output], Rake::Task[:generate_parser].prerequisites
      Rake::Task[:generate_parser].invoke
      assert File.exist?(output)
    end
  end

  def test_requires_a_grammar_path
    error = assert_raises(ArgumentError) { Ibex::RakeTask.new(:parser) }
    assert_match(/grammar is required/, error.message)
  end

  def test_up_to_date_file_task_does_not_rewrite_the_target
    Dir.mktmpdir do |directory|
      grammar = File.join(directory, "parser.y")
      output = File.join(directory, "parser.rb")
      File.write(grammar, "class Parser\nrule\nstart: TOKEN\nend\n")
      File.write(output, "# already generated\n")
      now = Time.now
      File.utime(now - 20, now - 20, grammar)
      File.utime(now, now, output)

      Ibex::RakeTask.new(output) { |task| task.grammar = grammar }
      Rake::Task[output].invoke

      assert_equal "# already generated\n", File.read(output)
    end
  end

  def test_invalid_grammar_fails_while_defining_the_task
    Dir.mktmpdir do |directory|
      grammar = File.join(directory, "broken.y")
      output = File.join(directory, "broken.rb")
      File.write(grammar, "not a grammar")

      error = assert_raises(Ibex::Error) do
        Ibex::RakeTask.new(output) { |task| task.grammar = grammar }
      end
      assert_match(/expected class/, error.message)
      refute Rake::Task.task_defined?(output)
      refute File.exist?(output)
    end
  end

  def test_broken_include_fails_definition_even_when_target_is_newer
    Dir.mktmpdir do |directory|
      grammar = File.join(directory, "root.y")
      output = File.join(directory, "parser.rb")
      File.write(grammar, "class P\ninclude \"missing.y\"\nrule\nstart: TOKEN\nend\n")
      File.write(output, "# stale output\n")
      now = Time.now
      File.utime(now - 20, now - 20, grammar)
      File.utime(now, now, output)

      error = assert_raises(Ibex::Error) do
        Ibex::RakeTask.new(output) do |task|
          task.grammar = grammar
          task.options = ["--mode=extended"]
        end
      end

      assert_match(/include file does not exist/, error.message)
      refute Rake::Task.task_defined?(output)
      assert_equal "# stale output\n", File.read(output)
    end
  end

  def test_included_fragments_are_canonical_file_prerequisites_in_dfs_order
    Dir.mktmpdir do |directory|
      root = File.join(directory, "root.y")
      fragment = File.join(directory, "fragment.y")
      shared = File.join(directory, "shared.y")
      output = File.join(directory, "parser.rb")
      File.write(root, "class P\ninclude \"fragment.y\"\nrule\nstart: helper\nend\n")
      File.write(fragment, "fragment\ninclude \"shared.y\"\nrule\nhelper: shared\nend\n")
      File.write(shared, "fragment\nrule\nshared: TOKEN\nend\n")

      Ibex::RakeTask.new(output) do |task|
        task.grammar = root
        task.options = ["--mode=extended"]
      end

      expected = [root, File.realpath(fragment), File.realpath(shared)]
      assert_equal expected, Rake::Task[output].prerequisites
    end
  end
end
