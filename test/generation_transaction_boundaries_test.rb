# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "tmpdir"

class GenerationTransactionBoundariesTest < Minitest::Test
  def test_same_size_source_change_during_staging_rejects_publication
    Dir.mktmpdir("ibex-boundary") do |directory|
      source = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      File.binwrite(source, "AAAA")
      File.binwrite(parser, "old parser")
      timestamp = File.mtime(source)
      input = Ibex::GenerationInput.new(source, "AAAA")
      checks = 0
      stable = lambda do
        checks += 1
        if checks == 1
          File.binwrite(source, "BBBB")
          File.utime(timestamp, timestamp, source)
          true
        else
          input.current?
        end
      end

      assert_raises(Ibex::GenerationTransaction::SourceChanged) do
        transaction(parser, "new parser", source_records: [input], stability_check: stable).commit
      end

      assert_equal "old parser", File.binread(parser)
      assert_empty generation_temporaries(directory)
    end
  end

  def test_change_after_manifest_install_rolls_back_the_complete_generation
    Dir.mktmpdir("ibex-boundary") do |directory|
      parser = File.join(directory, "parser.rb")
      manifest = File.join(directory, "parser.ibex.json")
      File.binwrite(parser, "old parser")
      File.binwrite(manifest, "old manifest")
      artifacts = Ibex::ArtifactSet.new
      artifacts.add(kind: :parser, path: parser, content: "new parser")
      artifacts.add(kind: :manifest, path: manifest, content: "new manifest")
      checks = 0
      stable = -> { (checks += 1) < 5 }

      assert_raises(Ibex::GenerationTransaction::SourceChanged) do
        Ibex::GenerationTransaction.new(artifacts, stability_check: stable).commit
      end

      assert_equal "old parser", File.binread(parser)
      assert_equal "old manifest", File.binread(manifest)
      assert_empty generation_temporaries(directory)
    end
  end

  def test_output_created_as_source_symlink_while_locking_is_rejected
    Dir.mktmpdir("ibex-boundary") do |directory|
      source = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      File.binwrite(source, "grammar")
      input = Ibex::GenerationInput.new(source, "grammar")
      original_new = File.method(:new)
      linked = false
      factory = lambda do |*arguments, **keywords|
        unless linked
          File.symlink(source, parser)
          linked = true
        end
        original_new.call(*arguments, **keywords)
      end

      error = File.stub(:new, factory) do
        assert_raises(Ibex::GenerationTransaction::Error) do
          transaction(parser, "generated", source_records: [input]).commit
        end
      end

      assert_match(/aliases generation input/, error.message)
      assert_equal "grammar", File.binread(source)
      assert File.symlink?(parser)
    end
  end

  def test_output_symlink_retarget_after_prepare_is_rejected_before_backup
    Dir.mktmpdir("ibex-boundary") do |directory|
      first = File.join(directory, "first.rb")
      second = File.join(directory, "second.rb")
      output = File.join(directory, "parser.rb")
      File.binwrite(first, "old first")
      File.binwrite(second, "old second")
      File.symlink("first.rb", output)
      changed = false
      stable = lambda do
        unless changed
          File.unlink(output)
          File.symlink("second.rb", output)
          changed = true
        end
        true
      end

      assert_raises(Ibex::GenerationTransaction::SourceChanged) do
        transaction(output, "generated", stability_check: stable).commit
      end

      assert_equal "old first", File.binread(first)
      assert_equal "old second", File.binread(second)
      assert_equal "second.rb", File.readlink(output)
    end
  end

  def test_lock_path_cannot_alias_a_generation_input
    Dir.mktmpdir("ibex-boundary") do |directory|
      canonical_directory = File.realpath(directory)
      parser = File.join(canonical_directory, "parser.rb")
      digest = Digest::SHA256.hexdigest(parser).slice(0, 16)
      source = File.join(canonical_directory, ".ibex-generation-#{digest}.lock")
      File.binwrite(source, "grammar")
      input = Ibex::GenerationInput.new(source, "grammar")

      error = assert_raises(Ibex::GenerationTransaction::Error) do
        transaction(parser, "generated", source_records: [input]).commit
      end

      assert_match(/lock aliases a protected path/, error.message)
      assert_equal "grammar", File.binread(source)
      refute File.exist?(parser)
    end
  end

  def test_nonblocking_lock_wait_sleeps_and_revalidates
    Dir.mktmpdir("ibex-boundary") do |directory|
      parser = File.join(directory, "parser.rb")
      original_new = File.method(:new)
      attempts = 0
      sleeps = 0
      factory = lambda do |*arguments, **keywords|
        lock = original_new.call(*arguments, **keywords)
        original_flock = File.instance_method(:flock).bind(lock)
        lock.define_singleton_method(:flock) do |operation|
          if operation.anybits?(File::LOCK_NB) && attempts.zero?
            attempts += 1
            false
          else
            original_flock.call(operation)
          end
        end
        lock
      end

      File.stub(:new, factory) do
        transaction(parser, "generated", lock_sleeper: ->(_seconds) { sleeps += 1 }).commit
      end

      assert_equal 1, sleeps
      assert_equal "generated", File.binread(parser)
    end
  end

  def test_recreated_lock_path_is_detected_before_publication
    Dir.mktmpdir("ibex-boundary") do |directory|
      parser = File.join(directory, "parser.rb")
      changed = false
      stable = lambda do
        unless changed
          lock = Dir.glob(File.join(File.realpath(directory), ".ibex-generation-*.lock")).fetch(0)
          File.unlink(lock)
          File.binwrite(lock, "replacement")
          changed = true
        end
        true
      end

      assert_raises(Ibex::GenerationTransaction::SourceChanged) do
        transaction(parser, "generated", stability_check: stable).commit
      end

      refute File.exist?(parser)
      assert_empty generation_temporaries(directory)
    end
  end

  private

  def transaction(path, content, **options)
    artifacts = Ibex::ArtifactSet.new
    artifacts.add(kind: :parser, path: path, content: content)
    Ibex::GenerationTransaction.new(artifacts, **options)
  end

  def generation_temporaries(directory)
    Dir.glob(File.join(directory, ".ibex-generation-*.{stage,backup}"))
  end
end
