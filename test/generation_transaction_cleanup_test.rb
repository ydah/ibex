# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class GenerationTransactionCleanupTest < Minitest::Test
  def test_best_effort_sync_continues_after_one_directory_fails
    Dir.mktmpdir("ibex-transaction") do |directory|
      first = File.join(directory, "first")
      second = File.join(directory, "second")
      Dir.mkdir(first)
      Dir.mkdir(second)
      transaction = Ibex::GenerationTransaction.new(Ibex::ArtifactSet.new)
      transaction.instance_variable_set(
        :@records, [{ directory: first }, { directory: second }]
      )
      calls = []
      original = File.method(:open)
      opener = lambda do |path, *arguments, &block|
        calls << path
        raise Errno::EIO, path if path == first

        original.call(path, *arguments, &block)
      end

      failures = File.stub(:open, opener) do
        transaction.__send__(:sync_directories_best_effort)
      end

      assert_equal [first, second], calls
      assert_equal 1, failures.length
    end
  end
end
