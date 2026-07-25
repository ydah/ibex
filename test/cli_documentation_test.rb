# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLIDocumentationTest < Minitest::Test
  def test_stdout_formats_are_deterministic_and_resolve_included_fragment_docs
    with_documented_include do |root, _fragment, _directory|
      rejected = invoke(["doc", root])
      assert_equal 1, rejected.fetch(:status)
      assert_empty rejected.fetch(:stdout)
      assert_match(/includes require extended mode/, rejected.fetch(:stderr))

      markdown = invoke(["doc", "--mode=extended", root])
      assert_equal 0, markdown.fetch(:status)
      assert_empty markdown.fetch(:stderr)
      assert_includes markdown.fetch(:stdout), "# Documentation grammar"
      assert_includes markdown.fetch(:stdout), "Included &lt;helper&gt;&amp;"

      html = invoke(["doc", "--mode=extended", "--format=html", root])
      assert_equal 0, html.fetch(:status)
      assert_includes html.fetch(:stdout), "<!doctype html>"
      assert_includes html.fetch(:stdout), "Included &lt;helper&gt;&amp;"

      railroad = invoke(["doc", "--mode=extended", "--format=railroad", root])
      assert_equal 0, railroad.fetch(:status)
      assert_includes railroad.fetch(:stdout), "<svg"
      assert_includes railroad.fetch(:stdout), "Included &lt;helper&gt;&amp;"
    end
  end

  def test_output_is_atomic_and_leaves_no_temporary_file
    with_documented_include do |root, fragment, directory|
      output = File.join(directory, "documentation.md")
      result = invoke(["doc", "--mode=extended", "-o", output, root])

      assert_equal 0, result.fetch(:status)
      assert_empty result.fetch(:stdout)
      assert_empty result.fetch(:stderr)
      assert_includes File.read(output), "Included &lt;helper&gt;&amp;"
      assert_equal [File.basename(output), File.basename(fragment), File.basename(root)].sort,
                   Dir.children(directory).sort
    end
  end

  def test_output_cannot_alias_an_included_fragment_directly_or_through_filesystem_aliases
    with_documented_include do |root, fragment, directory|
      original = File.binread(fragment)

      direct = invoke(["doc", "--mode=extended", "-o", fragment, root])
      assert_documentation_collision(direct, fragment, original)

      symlink = File.join(directory, "fragment-symlink.md")
      File.symlink(fragment, symlink)
      through_symlink = invoke(["doc", "--mode=extended", "-o", symlink, root])
      assert_documentation_collision(through_symlink, fragment, original)
      assert File.symlink?(symlink)

      hardlink = File.join(directory, "fragment-hardlink.md")
      File.link(fragment, hardlink)
      through_hardlink = invoke(["doc", "--mode=extended", "-o", hardlink, root])
      assert_documentation_collision(through_hardlink, fragment, original)
    end
  rescue NotImplementedError, Errno::EACCES, Errno::EPERM
    skip "filesystem aliases are not available"
  end

  def test_errors_do_not_replace_output_and_reject_input_collisions
    Dir.mktmpdir("ibex-cli-doc-errors") do |directory|
      root = File.join(directory, "root.y")
      output = File.join(directory, "documentation.md")
      File.write(root, <<~GRAMMAR)
        class P
        rule
        ## First.
        value: FIRST
        ## Different.
        value: SECOND
        end
      GRAMMAR
      File.write(output, "keep\n")

      conflict = invoke(["doc", "-o", output, root])
      assert_equal 1, conflict.fetch(:status)
      assert_match(/conflicting documentation/, conflict.fetch(:stderr))
      assert_equal "keep\n", File.read(output)

      original = File.read(root)
      collision = invoke(["doc", "-o", root, root])
      assert_equal 1, collision.fetch(:status)
      assert_match(/input and output paths must be distinct/, collision.fetch(:stderr))
      assert_equal original, File.read(root)

      invalid = invoke(["doc", "--format=pdf", root])
      assert_equal 1, invalid.fetch(:status)
      assert_match(/invalid argument.*format/i, invalid.fetch(:stderr))
    end
  end

  def test_help_and_missing_input_have_explicit_results
    help = invoke(%w[doc --help])
    assert_equal 0, help.fetch(:status)
    assert_match(/Usage: ibex doc/, help.fetch(:stdout))
    assert_empty help.fetch(:stderr)

    missing = invoke(["doc"])
    assert_equal 1, missing.fetch(:status)
    assert_empty missing.fetch(:stdout)
    assert_match(/grammar file is required/, missing.fetch(:stderr))
  end

  private

  def with_documented_include
    Dir.mktmpdir("ibex-cli-doc") do |directory|
      root = File.join(directory, "root.y")
      fragment = File.join(directory, "fragment.y")
      File.write(root, <<~GRAMMAR)
        class Documentation
        include "fragment.y"
        rule
        ## Root rule.
        start: helper
        end
      GRAMMAR
      File.write(fragment, <<~GRAMMAR)
        fragment
        rule
        ## Included <helper>&.
        helper: TOKEN
        end
      GRAMMAR
      yield root, fragment, directory
    end
  end

  def invoke(arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
    { status: status, stdout: stdout.string, stderr: stderr.string }
  end

  def assert_documentation_collision(result, fragment, original)
    assert_equal 1, result.fetch(:status)
    assert_empty result.fetch(:stdout)
    assert_match(/output aliases grammar source/, result.fetch(:stderr))
    assert_equal original, File.binread(fragment)
  end
end
