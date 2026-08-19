# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class GenerationTransactionTest < Minitest::Test
  def test_publishes_all_artifacts_and_preserves_existing_modes
    Dir.mktmpdir("ibex-transaction") do |directory|
      parser = File.join(directory, "parser.rb")
      report = File.join(directory, "parser.output")
      File.binwrite(parser, "old parser")
      File.chmod(0o640, parser)
      artifacts = artifact_set(parser => "new parser", report => "new report")

      Ibex::GenerationTransaction.new(artifacts).commit

      assert_equal "new parser", File.binread(parser)
      assert_equal "new report", File.binread(report)
      assert_equal 0o640, File.stat(parser).mode & 0o777
    end
  end

  def test_new_mode_obeys_umask_and_explicit_executable_mode
    Dir.mktmpdir("ibex-transaction") do |directory|
      parser = File.join(directory, "parser.rb")
      report = File.join(directory, "parser.output")
      artifacts = Ibex::ArtifactSet.new
      artifacts.add(kind: :report, path: report, content: "report")
      artifacts.add(kind: :parser, path: parser, content: "parser", mode: 0o755)
      previous = File.umask(0o027)
      begin
        Ibex::GenerationTransaction.new(artifacts).commit
      ensure
        File.umask(previous)
      end

      assert_equal 0o640, File.stat(report).mode & 0o777
      assert_equal 0o755, File.stat(parser).mode & 0o777
    end
  end

  def test_preserves_relative_and_dangling_symlinks
    Dir.mktmpdir("ibex-transaction") do |directory|
      targets = File.join(directory, "targets")
      Dir.mkdir(targets)
      existing_target = File.join(targets, "existing.rb")
      dangling_target = File.join(targets, "new.rbs")
      parser = File.join(directory, "parser.rb")
      signature = File.join(directory, "parser.rbs")
      File.binwrite(existing_target, "old")
      File.symlink("targets/existing.rb", parser)
      File.symlink("targets/new.rbs", signature)
      artifacts = artifact_set(parser => "parser", signature => "signature")

      Ibex::GenerationTransaction.new(artifacts).commit

      assert File.symlink?(parser)
      assert File.symlink?(signature)
      assert_equal "targets/existing.rb", File.readlink(parser)
      assert_equal "targets/new.rbs", File.readlink(signature)
      assert_equal "parser", File.binread(existing_target)
      assert_equal "signature", File.binread(dangling_target)
    end
  end

  def test_rejects_hard_linked_targets
    Dir.mktmpdir("ibex-transaction") do |directory|
      parser = File.join(directory, "parser.rb")
      alias_path = File.join(directory, "parser-alias.rb")
      File.binwrite(parser, "old")
      File.link(parser, alias_path)

      error = assert_raises(Ibex::GenerationTransaction::Error) do
        Ibex::GenerationTransaction.new(artifact_set(parser => "new")).commit
      end

      assert_match(/multiple hard links/, error.message)
      assert_equal "old", File.binread(parser)
    end
  end

  def test_rejects_filesystems_without_directory_fsync
    Dir.mktmpdir("ibex-transaction") do |directory|
      parser = File.join(directory, "parser.rb")
      error = assert_raises(Ibex::GenerationTransaction::Error) do
        File.stub(:open, ->(*_args) { raise Errno::ENOTSUP, "directory fsync" }) do
          Ibex::GenerationTransaction.new(artifact_set(parser => "new")).commit
        end
      end

      assert_match(/requires POSIX directory fsync support/, error.message)
      refute File.exist?(parser)
    end
  end

  def test_rejects_portability_collisions_before_writing
    Dir.mktmpdir("ibex-transaction") do |directory|
      parser = File.join(directory, "Parser.rb")
      signature = File.join(directory, "parser.rb")
      artifacts = artifact_set(parser => "parser", signature => "signature")

      error = assert_raises(Ibex::GenerationTransaction::Error) do
        Ibex::GenerationTransaction.new(artifacts).commit
      end

      assert_match(/artifact targets collide/, error.message)
      refute File.exist?(parser)
      refute File.exist?(signature)
    end
  end

  def test_rejects_unicode_normalization_collisions_before_writing
    Dir.mktmpdir("ibex-transaction") do |directory|
      composed = File.join(directory, "Caf\u00e9.rb")
      decomposed = File.join(directory, "Cafe\u0301.rb")
      artifacts = artifact_set(composed => "parser", decomposed => "signature")

      assert_raises(Ibex::GenerationTransaction::Error) do
        Ibex::GenerationTransaction.new(artifacts).commit
      end
      refute File.exist?(composed)
      refute File.exist?(decomposed)
    end
  end

  def test_rejects_full_unicode_case_fold_collisions_before_writing
    Dir.mktmpdir("ibex-transaction") do |directory|
      capital_sigma = File.join(directory, "\u03a3.rb")
      final_sigma = File.join(directory, "\u03c2.rb")
      artifacts = artifact_set(capital_sigma => "parser", final_sigma => "signature")

      assert_raises(Ibex::GenerationTransaction::Error) do
        Ibex::GenerationTransaction.new(artifacts).commit
      end
      refute File.exist?(capital_sigma)
      refute File.exist?(final_sigma)
    end
  end

  private

  def artifact_set(paths)
    paths.each_with_object(Ibex::ArtifactSet.new) do |(path, content), artifacts|
      kind = File.extname(path) == ".rb" ? :parser : :report
      artifacts.add(kind: kind, path: path, content: content)
    end
  end
end
