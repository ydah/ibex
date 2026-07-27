# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class GenerationTransactionRecoveryTest < Minitest::Test
  def test_rolls_back_installed_and_backed_up_targets_when_parser_publish_fails
    Dir.mktmpdir("ibex-transaction") do |directory|
      parser = File.join(directory, "parser.rb")
      report = File.join(directory, "parser.output")
      manifest = File.join(directory, "parser.ibex.json")
      write_files(parser => "old parser", report => "old report", manifest => "old manifest")
      artifacts = artifact_set(
        report: [report, "new report"], parser: [parser, "new parser"], manifest: [manifest, "new manifest"]
      )
      rename = fail_parser_install(File.realpath(parser))

      File.stub(:rename, rename) do
        assert_raises(Ibex::GenerationTransaction::Error) do
          Ibex::GenerationTransaction.new(artifacts).commit
        end
      end

      assert_equal "old parser", File.binread(parser)
      assert_equal "old report", File.binread(report)
      assert_equal "old manifest", File.binread(manifest)
      assert_empty Dir.glob(File.join(directory, ".ibex-generation-*.{stage,backup}"))
    end
  end

  def test_cleanup_failure_is_a_warning_after_successful_publication
    Dir.mktmpdir("ibex-transaction") do |directory|
      parser = File.join(directory, "parser.rb")
      File.binwrite(parser, "old")
      warnings = []
      unlink = fail_backup_cleanup

      File.stub(:unlink, unlink) do
        Ibex::GenerationTransaction.new(
          artifact_set(parser: [parser, "new"]), warning: ->(message) { warnings << message }
        ).commit
      end

      assert_equal "new", File.binread(parser)
      assert_match(/cleanup incomplete/, warnings.fetch(0))
      Dir.glob(File.join(directory, ".ibex-generation-*.backup")).each { |path| File.unlink(path) }
    end
  end

  def test_rollback_failure_preserves_and_reports_recovery_artifact
    Dir.mktmpdir("ibex-transaction") do |directory|
      parser = File.join(directory, "parser.rb")
      report = File.join(directory, "parser.output")
      write_files(parser => "old parser", report => "old report")
      artifacts = artifact_set(report: [report, "new report"], parser: [parser, "new parser"])
      rename = fail_parser_install_and_report_rollback(File.realpath(parser), File.realpath(report))

      error = File.stub(:rename, rename) do
        assert_raises(Ibex::GenerationTransaction::Error) do
          Ibex::GenerationTransaction.new(artifacts).commit
        end
      end

      assert error.rollback_failed
      refute_empty error.recovery_artifacts
      assert_match(/recovery artifacts/, error.message)
      assert(error.recovery_artifacts.all? { |path| File.exist?(path) })
    end
  end

  def test_parallel_publishers_leave_one_complete_generation
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    Dir.mktmpdir("ibex-transaction") do |directory|
      parser = File.join(directory, "parser.rb")
      report = File.join(directory, "parser.output")
      manifest = File.join(directory, "parser.ibex.json")
      children, writers = spawn_publishers(parser, report, manifest)
      writers.each do |writer|
        writer.write(".")
        writer.close
      end
      children.each do |pid|
        _child, status = Process.wait2(pid)
        assert status.success?
      end

      label = File.binread(manifest)
      assert_includes %w[A B], label
      assert_equal "parser #{label}", File.binread(parser)
      assert_equal "report #{label}", File.binread(report)
    end
  end

  def test_warning_callback_failure_after_commit_does_not_trigger_rollback
    Dir.mktmpdir("ibex-transaction") do |directory|
      parser = File.join(directory, "parser.rb")
      File.binwrite(parser, "old")
      unlink = fail_backup_cleanup

      File.stub(:unlink, unlink) do
        Ibex::GenerationTransaction.new(
          artifact_set(parser: [parser, "new"]),
          warning: ->(_message) { raise Errno::EPIPE, "closed warning stream" }
        ).commit
      end

      assert_equal "new", File.binread(parser)
    end
  end

  def test_cleanup_attempts_every_backup_after_independent_failures
    Dir.mktmpdir("ibex-transaction") do |directory|
      paths = %w[report.output parser.rb parser.ibex.json].to_h do |name|
        path = File.join(directory, name)
        File.binwrite(path, "old")
        [path, "new"]
      end
      artifacts = artifact_set(
        report: paths.to_a.fetch(0), parser: paths.to_a.fetch(1), manifest: paths.to_a.fetch(2)
      )
      attempts = Hash.new(0)
      cleanup_attempts = []
      original = File.method(:unlink)
      unlink = lambda do |path|
        if path.include?(".backup")
          attempts[path] += 1
          if attempts[path] == 1
            cleanup_attempts << path
            raise Errno::EACCES, path
          end
        end
        original.call(path)
      end

      File.stub(:unlink, unlink) { Ibex::GenerationTransaction.new(artifacts).commit }

      assert_equal 3, cleanup_attempts.length
      assert(paths.all? { |path, content| File.binread(path) == content })
      cleanup_attempts.each { |path| File.unlink(path) }
    end
  end

  private

  def artifact_set(entries)
    entries.each_with_object(Ibex::ArtifactSet.new) do |(kind, (path, content)), artifacts|
      artifacts.add(kind: kind, path: path, content: content)
    end
  end

  def write_files(paths)
    paths.each { |path, content| File.binwrite(path, content) }
  end

  def fail_parser_install(parser_target)
    original = File.method(:rename)
    failed = false
    lambda do |source, target|
      if target == parser_target && File.basename(source).include?(".stage") && !failed
        failed = true
        raise Errno::EIO, target
      end
      original.call(source, target)
    end
  end

  def fail_backup_cleanup
    original = File.method(:unlink)
    backup_unlinks = 0
    lambda do |path|
      backup_unlinks += 1 if path.include?(".backup")
      raise Errno::EACCES, path if path.include?(".backup") && backup_unlinks == 1

      original.call(path)
    end
  end

  def fail_parser_install_and_report_rollback(parser_target, report_target)
    original = File.method(:rename)
    parser_failed = false
    lambda do |source, target|
      if target == parser_target && File.basename(source).include?(".stage") && !parser_failed
        parser_failed = true
        raise Errno::EIO, target
      end
      if parser_failed && target == report_target && File.basename(source).include?(".backup")
        raise Errno::EACCES, target
      end

      original.call(source, target)
    end
  end

  def spawn_publishers(parser, report, manifest)
    writers = []
    children = 2.times.map do |index|
      reader, writer = IO.pipe
      writers << writer
      pid = fork do
        writer.close
        reader.read(1)
        label = index.zero? ? "A" : "B"
        artifacts = artifact_set(
          report: [report, "report #{label}"], parser: [parser, "parser #{label}"], manifest: [manifest, label]
        )
        Ibex::GenerationTransaction.new(artifacts).commit
        exit! 0
      end
      reader.close
      pid
    end
    [children, writers]
  end
end
