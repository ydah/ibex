# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class GenerationTransactionLockTest < Minitest::Test
  def test_lock_wait_cancellation_fails_closed_without_sleeping
    Dir.mktmpdir("ibex-lock") do |directory|
      parser = File.join(directory, "parser.rb")
      artifacts = Ibex::ArtifactSet.new
      artifacts.add(kind: :parser, path: parser, content: "generated")
      original_new = File.method(:new)
      sleeps = 0
      factory = lambda do |*arguments, **keywords|
        lock = original_new.call(*arguments, **keywords)
        original_flock = File.instance_method(:flock).bind(lock)
        lock.define_singleton_method(:flock) do |operation|
          operation.anybits?(File::LOCK_NB) ? false : original_flock.call(operation)
        end
        lock
      end

      File.stub(:new, factory) do
        assert_raises(Ibex::GenerationTransaction::SourceChanged) do
          Ibex::GenerationTransaction.new(
            artifacts,
            stability_check: -> { false },
            lock_sleeper: ->(_seconds) { sleeps += 1 }
          ).commit
        end
      end

      assert_equal 0, sleeps
      refute File.exist?(parser)
    end
  end
end
