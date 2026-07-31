# frozen_string_literal: true

require_relative "test_helper"
require "rbconfig"
require "ibex/bounded_subprocess"
require "tmpdir"

class BoundedSubprocessTest < Minitest::Test
  def test_captures_a_normal_exit_without_a_shell
    result = Ibex::BoundedSubprocess.new(
      timeout_seconds: 2, max_output_bytes: 100
    ).run([RbConfig.ruby, "-e", "STDOUT.write(STDIN.read.upcase)"], input: "ok")

    assert_predicate result.status, :success?
    assert_equal "OK", result.stdout
    refute result.timed_out
    refute result.output_limited
  end

  def test_terminates_a_timed_out_child
    result = Ibex::BoundedSubprocess.new(
      timeout_seconds: 1, max_output_bytes: 100
    ).run([RbConfig.ruby, "-e", "sleep 10"], input: "")

    assert result.timed_out
    refute_predicate result.status, :success?
  end

  def test_terminates_a_child_that_exceeds_the_output_budget
    result = Ibex::BoundedSubprocess.new(
      timeout_seconds: 2, max_output_bytes: 16
    ).run([RbConfig.ruby, "-e", "STDOUT.write('x' * 100_000); sleep 10"], input: "")

    assert result.output_limited
    assert_operator result.stdout.bytesize, :<=, 16
    refute_predicate result.status, :success?
  end

  def test_timeout_terminates_descendants_in_the_child_process_group
    skip "forked process groups are unavailable" unless Process.respond_to?(:fork)

    Dir.mktmpdir("ibex-subprocess-group") do |directory|
      marker = File.join(directory, "leaked")
      script = "fork { sleep 1.25; File.binwrite(ARGV.fetch(0), 'leaked') }; sleep 10"

      result = Ibex::BoundedSubprocess.new(
        timeout_seconds: 1, max_output_bytes: 100
      ).run([RbConfig.ruby, "-e", script, marker], input: "")
      sleep 0.5

      assert result.timed_out
      refute_path_exists marker
    end
  end

  def test_normal_parent_exit_does_not_leave_a_descendant_running
    skip "forked process groups are unavailable" unless Process.respond_to?(:fork)

    Dir.mktmpdir("ibex-subprocess-group") do |directory|
      marker = File.join(directory, "leaked")
      script = "fork { sleep 0.5; File.binwrite(ARGV.fetch(0), 'leaked') }"

      result = Ibex::BoundedSubprocess.new(
        timeout_seconds: 2, max_output_bytes: 100
      ).run([RbConfig.ruby, "-e", script, marker], input: "")
      sleep 0.75

      assert_predicate result.status, :success?
      refute_path_exists marker
    end
  end
end
