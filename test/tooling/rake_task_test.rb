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

  def test_generation_failure_fails_the_task_without_creating_a_target
    Dir.mktmpdir do |directory|
      grammar = File.join(directory, "broken.y")
      output = File.join(directory, "broken.rb")
      File.write(grammar, "not a grammar")
      Ibex::RakeTask.new(output) { |task| task.grammar = grammar }

      _stdout, _stderr = capture_io do
        error = assert_raises(RuntimeError) { Rake::Task[output].invoke }
        assert_match(/parser generation failed/, error.message)
      end
      refute File.exist?(output)
    end
  end
end
