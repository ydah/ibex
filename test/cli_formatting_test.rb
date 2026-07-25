# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

# rubocop:disable Metrics/ClassLength -- CLI transaction failure modes require end-to-end coverage.
class CLIFormattingTest < Minitest::Test
  def test_formats_one_file_to_stdout
    with_file("class  P token A rule value:A end") do |path, _directory|
      result = invoke(["fmt", path])

      assert_equal 0, result.fetch(:status)
      assert_equal "class P\ntoken A\nrule\n  value : A\nend\n", result.fetch(:stdout)
      assert_empty result.fetch(:stderr)
      assert_equal "class  P token A rule value:A end", File.binread(path)
    end
  end

  def test_formats_standard_input_with_a_diagnostic_filename
    result = invoke(
      ["fmt", "--stdin-filename=pipe.y", "-"],
      stdin: "class P\nrule\nbroken: (\nend\n"
    )

    assert_equal 1, result.fetch(:status)
    assert_empty result.fetch(:stdout)
    assert_match(/pipe\.y:/, result.fetch(:stderr))
  end

  def test_deep_extended_input_is_stack_safe_and_stack_errors_are_rendered_without_a_trace
    depth = 1_000
    nested = "#{'(' * depth}A#{')' * depth}"
    source = "class P\npragma extended\nrule\nvalue: #{nested}\nend\n"

    formatted = invoke(["fmt", "--mode=extended", "-"], stdin: source)
    assert_equal 0, formatted.fetch(:status)
    assert_empty formatted.fetch(:stderr)

    Ibex::Frontend::Formatter.stub(:format, ->(*) { raise SystemStackError, "stack level too deep" }) do
      failed = invoke(["fmt", "-"], stdin: source)
      assert_equal 1, failed.fetch(:status)
      assert_equal "stack level too deep\n", failed.fetch(:stderr)
    end
  end

  def test_control_characters_are_rejected_or_escaped_in_diagnostic_filenames
    stdin_result = invoke(
      ["fmt", "--stdin-filename=bad\nname.y", "-"],
      stdin: "class P\nrule\nvalue: A\nend\n"
    )
    assert_equal 1, stdin_result.fetch(:status)
    assert_equal 1, stdin_result.fetch(:stderr).lines.length
    assert_includes stdin_result.fetch(:stderr), "control characters"

    unicode_result = invoke(
      ["fmt", "--stdin-filename=日本語文法.y", "-"],
      stdin: "class P\nrule\nvalue: A\nend\n"
    )
    assert_equal 0, unicode_result.fetch(:status)
    assert_empty unicode_result.fetch(:stderr)

    Dir.mktmpdir("ibex-fmt-control") do |directory|
      path = File.join(directory, "bad\nname.y")
      File.write(path, "class  P rule value:A end")
      file_result = invoke(["fmt", "--check", path])

      assert_equal 1, file_result.fetch(:status)
      assert_equal 1, file_result.fetch(:stderr).lines.length
      assert_includes file_result.fetch(:stderr), "bad\\x0Aname.y: needs formatting"
    end
  rescue ArgumentError, Errno::EINVAL
    skip "filesystem does not support control bytes in file names"
  end

  def test_check_processes_every_file_and_reports_parse_errors_and_differences
    Dir.mktmpdir("ibex-fmt-check") do |directory|
      changed = File.join(directory, "changed.y")
      invalid = File.join(directory, "invalid.y")
      invalid_too = File.join(directory, "invalid-too.y")
      clean = File.join(directory, "clean.y")
      File.write(changed, "class  Changed rule value:A end")
      File.write(invalid, "class Invalid\nrule\nvalue: (\nend\n")
      File.write(invalid_too, "class AlsoInvalid\nrule\nvalue: @\nend\n")
      File.write(clean, "class Clean\nrule\n  value : A\nend\n")

      result = invoke(["fmt", "--check", changed, invalid, invalid_too, clean])

      assert_equal 1, result.fetch(:status)
      assert_empty result.fetch(:stdout)
      assert_includes result.fetch(:stderr), "#{changed}: needs formatting"
      assert_match(/#{Regexp.escape(invalid)}:/, result.fetch(:stderr))
      assert_match(/#{Regexp.escape(invalid_too)}:/, result.fetch(:stderr))
      refute_includes result.fetch(:stderr), "#{clean}: needs formatting"
    end
  end

  def test_check_succeeds_when_every_file_is_formatted
    with_file("class P\nrule\n  value : A\nend\n") do |path, _directory|
      result = invoke(["fmt", "--check", path])

      assert_equal 0, result.fetch(:status)
      assert_empty result.fetch(:stdout)
      assert_empty result.fetch(:stderr)
    end
  end

  def test_write_is_atomic_preserves_mode_and_leaves_no_temporary_file
    with_file("class  P rule value:A end") do |path, directory|
      File.chmod(0o751, path)

      result = invoke(["fmt", "--write", path])

      assert_equal 0, result.fetch(:status)
      assert_empty result.fetch(:stdout)
      assert_empty result.fetch(:stderr)
      assert_equal "class P\nrule\n  value : A\nend\n", File.binread(path)
      assert_equal 0o751, File.stat(path).mode & 0o777
      assert_equal [File.basename(path)], Dir.children(directory)
    end
  end

  def test_write_preserves_special_permission_bits
    with_file("class  P rule value:A end") do |path, _directory|
      File.chmod(0o4755, path)
      skip "filesystem does not retain set-ID mode bits" unless (File.stat(path).mode & 0o7777) == 0o4755

      result = invoke(["fmt", "--write", path])

      assert_equal 0, result.fetch(:status)
      assert_equal 0o4755, File.stat(path).mode & 0o7777
    end
  rescue Errno::EACCES, Errno::EPERM
    skip "setting special permission bits is not permitted"
  end

  def test_write_supports_a_252_byte_target_basename
    Dir.mktmpdir("ibex-fmt-long") do |directory|
      path = File.join(directory, "#{'a' * 250}.y")
      File.write(path, "class  P rule value:A end")

      result = invoke(["fmt", "--write", path])

      assert_equal 0, result.fetch(:status)
      assert_equal "class P\nrule\n  value : A\nend\n", File.binread(path)
      assert_equal [File.basename(path)], Dir.children(directory)
    end
  rescue Errno::ENAMETOOLONG
    skip "filesystem does not support 252-byte basenames"
  end

  def test_write_preserves_a_symlink_and_replaces_its_target
    Dir.mktmpdir("ibex-fmt-link") do |directory|
      target = File.join(directory, "target.y")
      link = File.join(directory, "grammar.y")
      File.write(target, "class  P rule value:A end")
      File.symlink(File.basename(target), link)

      result = invoke(["fmt", "--write", link])

      assert_equal 0, result.fetch(:status)
      assert File.symlink?(link)
      assert_equal File.basename(target), File.readlink(link)
      assert_equal "class P\nrule\n  value : A\nend\n", File.binread(target)
    end
  rescue NotImplementedError, Errno::EACCES, Errno::EPERM
    skip "symbolic links are not available"
  end

  def test_write_validates_all_inputs_before_modifying_any_file
    Dir.mktmpdir("ibex-fmt-invalid") do |directory|
      valid = File.join(directory, "valid.y")
      invalid = File.join(directory, "invalid.y")
      File.write(valid, "class  Valid rule value:A end")
      File.write(invalid, "class Invalid\nrule\nvalue: (\nend\n")
      original = File.binread(valid)

      result = invoke(["fmt", "--write", valid, invalid])

      assert_equal 1, result.fetch(:status)
      assert_equal original, File.binread(valid)
    end
  end

  def test_atomic_rename_failure_leaves_the_original_and_removes_the_temporary_file
    with_file("class  P rule value:A end") do |path, directory|
      original = File.binread(path)

      File.stub(:rename, ->(*) { raise Errno::EACCES, path }) do
        result = invoke(["fmt", "--write", path])
        assert_equal 1, result.fetch(:status)
        assert_match(/Permission denied/, result.fetch(:stderr))
      end

      assert_equal original, File.binread(path)
      assert_equal [File.basename(path)], Dir.children(directory)
    end
  end

  def test_second_rename_failure_rolls_back_every_target_and_relative_symlink
    with_rollback_files do |directory, first, second_target, second_link, originals|
      fail_second_stage_rename do
        result = invoke(["fmt", "--write", first, second_link])
        assert_equal 1, result.fetch(:status)
      end

      assert_equal originals.fetch(first), File.binread(first)
      assert_equal originals.fetch(second_target), File.binread(second_target)
      assert_equal 0o640, File.stat(first).mode & 0o777
      assert_equal 0o750, File.stat(second_target).mode & 0o777
      assert File.symlink?(second_link)
      assert_equal File.basename(second_target), File.readlink(second_link)
      assert_equal %w[first.y second-target.y second.y], Dir.children(directory).sort
    end
  rescue NotImplementedError, Errno::EACCES, Errno::EPERM
    skip "symbolic links are not available"
  end

  def test_directory_fsync_failure_rolls_back_every_target
    Dir.mktmpdir("ibex-fmt-fsync") do |directory|
      first = File.join(directory, "first.y")
      second = File.join(directory, "second.y")
      File.write(first, "class  First rule value:A end")
      File.write(second, "class  Second rule value:B end")
      originals = [File.binread(first), File.binread(second)]
      stdout = StringIO.new
      stderr = StringIO.new
      cli = Ibex::CLI.new(stdin: StringIO.new, stdout: stdout, stderr: stderr)
      sync_count = 0
      sync = lambda do |_path|
        sync_count += 1
        raise Errno::EIO, directory if sync_count == 2
      end

      status = cli.stub(:sync_formatting_directory, sync) do
        cli.run(["fmt", "--write", first, second])
      end

      assert_equal 1, status
      assert_match(%r{Input/output error}, stderr.string)
      assert_equal originals, [File.binread(first), File.binread(second)]
      assert_equal %w[first.y second.y], Dir.children(directory).sort
    end
  end

  def test_rollback_rename_failure_preserves_the_exact_backup_and_reports_its_path
    with_file("class  P rule value:A end") do |path, directory|
      original = File.binread(path)
      result = invoke_with_failed_rollback(path)
      backup_path = result.fetch(:backup_path)

      assert_equal 1, result.fetch(:status)
      assert_includes result.fetch(:stderr), "Input/output error"
      assert_includes result.fetch(:stderr), "rollback failed"
      assert_includes result.fetch(:stderr), "preserved artifacts"
      refute_nil backup_path
      assert_includes result.fetch(:stderr), backup_path
      assert_equal original, File.binread(backup_path)
      assert_equal "class P\nrule\n  value : A\nend\n", File.binread(path)
      assert_equal [File.basename(backup_path), File.basename(path)].sort, Dir.children(directory).sort
    end
  end

  def test_committed_cleanup_failure_warns_retries_and_continues_all_artifacts
    [1, 2].each do |failure_index|
      with_two_formatting_files("ibex-fmt-cleanup") do |directory, first, second|
        original_unlink = File.method(:unlink)
        backup_paths = [] #: Array[String]
        blocked_path = nil
        unlink = lambda do |path|
          if path.end_with?(".backup")
            backup_paths << path unless backup_paths.include?(path)
            blocked_path ||= path if backup_paths.length == failure_index
            raise Errno::EACCES, path if path == blocked_path
          end
          original_unlink.call(path)
        end

        result = File.stub(:unlink, unlink) { invoke(["fmt", "--write", first, second]) }

        assert_equal 0, result.fetch(:status)
        assert_includes result.fetch(:stderr), "formatted targets committed"
        assert_includes result.fetch(:stderr), blocked_path
        assert_equal "class First\nrule\n  value : A\nend\n", File.binread(first)
        assert_equal "class Second\nrule\n  value : B\nend\n", File.binread(second)
        leftovers = Dir.children(directory).grep(/ibex-fmt/)
        assert_equal [File.basename(blocked_path)], leftovers
        original_unlink.call(blocked_path)
      end
    end
  end

  def test_cleanup_error_is_appended_without_masking_the_original_failure
    with_file("class  P rule value:A end") do |path, directory|
      original = File.binread(path)
      stdout = StringIO.new
      stderr = StringIO.new
      cli = Ibex::CLI.new(stdin: StringIO.new, stdout: stdout, stderr: stderr)
      cli_sync = ->(_directory) { raise Errno::EIO, directory }
      original_unlink = File.method(:unlink)
      backup_path = nil
      unlink = lambda do |artifact|
        if artifact.end_with?(".backup")
          backup_path = artifact
          raise Errno::EACCES, artifact
        end
        original_unlink.call(artifact)
      end

      status = cli.stub(:sync_formatting_directory, cli_sync) do
        File.stub(:unlink, unlink) { cli.run(["fmt", "--write", path]) }
      end

      assert_equal 1, status
      assert_includes stderr.string, "directory sync failed"
      assert_includes stderr.string, "cleanup failed"
      assert_includes stderr.string, "Permission denied"
      assert_includes stderr.string, backup_path
      assert_equal original, File.binread(path)
      assert_equal original, File.binread(backup_path)
      original_unlink.call(backup_path)
    end
  end

  def test_rollback_directory_sync_attempts_every_affected_directory
    with_formatting_files_in_separate_directories do |directories, paths|
      originals = paths.map { |path| File.binread(path) }
      sync_counts = Hash.new(0)
      result = invoke_with_repeated_directory_sync_failures(paths, sync_counts)

      assert_equal 1, result.fetch(:status)
      canonical_directories = directories.map { |directory| File.realpath(directory) }
      assert_equal({ canonical_directories.fetch(0) => 3, canonical_directories.fetch(1) => 3 }, sync_counts)
      canonical_directories.each { |directory| assert_includes result.fetch(:stderr), directory }
      restored = paths.map { |path| File.binread(path) }
      assert_equal originals, restored
      directories.each { |directory| assert_equal ["grammar.y"], Dir.children(directory) }
    end
  end

  def test_write_rejects_duplicate_and_aliased_targets_before_staging
    with_file("class P\nrule\n  value : A\nend\n") do |path, directory|
      duplicate = invoke(["fmt", "--write", path, path])

      assert_equal 1, duplicate.fetch(:status)
      assert_match(/same target/, duplicate.fetch(:stderr))
      assert_equal [File.basename(path)], Dir.children(directory)
    end

    Dir.mktmpdir("ibex-fmt-alias") do |directory|
      target = File.join(directory, "target.y")
      symlink = File.join(directory, "symlink.y")
      hardlink = File.join(directory, "hardlink.y")
      source = "class  P rule value:A end"
      File.write(target, source)
      File.symlink(File.basename(target), symlink)
      File.link(target, hardlink)

      [symlink, hardlink].each do |alias_path|
        result = invoke(["fmt", "--write", target, alias_path])
        assert_equal 1, result.fetch(:status)
        assert_match(/same target/, result.fetch(:stderr))
        assert_equal source, File.binread(target)
      end
      assert_equal %w[hardlink.y symlink.y target.y], Dir.children(directory).sort
    end
  rescue NotImplementedError, Errno::EACCES, Errno::EPERM
    skip "filesystem aliases are not available"
  end

  def test_rejects_generation_options_and_invalid_mode_combinations
    with_file("class P\nrule\n  value : A\nend\n") do |path, _directory|
      [
        ["fmt", "--emit=ast", path],
        ["fmt", "--rbs", path],
        ["fmt", "-o", "parser.rb", path],
        ["fmt", "--table=plain", path],
        ["fmt", "--check", "--write", path],
        ["fmt", "--write", "-"],
        ["fmt", "--stdin-filename=stdin.y", path],
        ["fmt", path, path]
      ].each do |arguments|
        result = invoke(arguments)
        assert_equal 1, result.fetch(:status), arguments.inspect
        refute_empty result.fetch(:stderr), arguments.inspect
      end
    end
  end

  def test_help_is_listed_and_available
    top = invoke(["--help"])
    help = invoke(["fmt", "--help"])

    assert_equal 0, top.fetch(:status)
    assert_includes top.fetch(:stdout), "fmt"
    assert_equal 0, help.fetch(:status)
    assert_match(/Usage: ibex fmt/, help.fetch(:stdout))
  end

  private

  def with_file(source)
    Dir.mktmpdir("ibex-fmt") do |directory|
      path = File.join(directory, "grammar.y")
      File.binwrite(path, source)
      yield path, directory
    end
  end

  def invoke(arguments, stdin: "")
    stdout = StringIO.new
    stderr = StringIO.new
    status = Ibex::CLI.start(arguments, stdin: StringIO.new(stdin), stdout: stdout, stderr: stderr)
    { status: status, stdout: stdout.string, stderr: stderr.string }
  end

  def with_two_formatting_files(prefix)
    Dir.mktmpdir(prefix) do |directory|
      first = File.join(directory, "first.y")
      second = File.join(directory, "second.y")
      File.write(first, "class  First rule value:A end")
      File.write(second, "class  Second rule value:B end")
      yield directory, first, second
    end
  end

  def with_formatting_files_in_separate_directories
    Dir.mktmpdir("ibex-fmt-multidir") do |root|
      directories = %w[first second].map do |name|
        directory = File.join(root, name)
        Dir.mkdir(directory)
        directory
      end
      paths = directories.each_with_index.map do |directory, index|
        path = File.join(directory, "grammar.y")
        File.write(path, "class  P#{index} rule value:A end")
        path
      end
      yield directories, paths
    end
  end

  def invoke_with_failed_rollback(path)
    stderr = StringIO.new
    cli = Ibex::CLI.new(stdin: StringIO.new, stdout: StringIO.new, stderr: stderr)
    sync_count = 0
    sync = lambda do |_directory|
      sync_count += 1
      raise Errno::EIO, path if sync_count == 2
    end
    original_rename = File.method(:rename)
    backup_path = nil
    rename = lambda do |from, to|
      if from.end_with?(".backup")
        backup_path = from
        raise Errno::EACCES, to
      end
      original_rename.call(from, to)
    end
    status = cli.stub(:sync_formatting_directory, sync) do
      File.stub(:rename, rename) { cli.run(["fmt", "--write", path]) }
    end
    { status: status, stderr: stderr.string, backup_path: backup_path }
  end

  def invoke_with_repeated_directory_sync_failures(paths, sync_counts)
    stderr = StringIO.new
    cli = Ibex::CLI.new(stdin: StringIO.new, stdout: StringIO.new, stderr: stderr)
    sync = lambda do |directory|
      sync_counts[directory] += 1
      raise Errno::EIO, directory if sync_counts.fetch(directory) >= 2
    end
    status = cli.stub(:sync_formatting_directory, sync) do
      cli.run(["fmt", "--write", *paths])
    end
    { status: status, stderr: stderr.string }
  end

  def with_rollback_files
    Dir.mktmpdir("ibex-fmt-rollback") do |directory|
      first = File.join(directory, "first.y")
      second_target = File.join(directory, "second-target.y")
      second_link = File.join(directory, "second.y")
      File.write(first, "class  First rule value:A end")
      File.write(second_target, "class  Second rule value:B end")
      File.chmod(0o640, first)
      File.chmod(0o750, second_target)
      File.symlink(File.basename(second_target), second_link)
      originals = { first => File.binread(first), second_target => File.binread(second_target) }
      yield directory, first, second_target, second_link, originals
    end
  end

  def fail_second_stage_rename(&block)
    original_rename = File.method(:rename)
    install_count = 0
    rename = lambda do |from, to|
      if File.basename(from).start_with?(".ibex-fmt-") && from.end_with?(".stage")
        install_count += 1
        raise Errno::EACCES, to if install_count == 2
      end
      original_rename.call(from, to)
    end
    File.stub(:rename, rename, &block)
  end
end
# rubocop:enable Metrics/ClassLength
