# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "tmpdir"

class FrontendResolverSecurityTest < Minitest::Test
  def test_cycle_reports_the_exact_canonical_chain
    in_directory do |directory|
      root = write(directory, "root.y", "class P\ninclude \"a.y\"\nrule\nstart: A\nend\n")
      a = write(directory, "a.y", "fragment\ninclude \"b.y\"\nrule\na: A\nend\n")
      b = write(directory, "b.y", "fragment\ninclude \"a.y\"\nrule\nb: A\nend\n")

      error = assert_raises(Ibex::Error) { resolve(root) }
      cycle = [a, b, a].map { |path| File.realpath(path) }.join(" -> ")
      assert_equal "#{File.realpath(b)}:2:1: include cycle: #{cycle}", error.message
    end
  end

  def test_symlink_aliases_participate_in_cycles_and_cannot_escape_the_root
    in_directory do |directory|
      root = write(directory, "root.y", "class P\ninclude \"alias.y\"\nrule\nstart: A\nend\n")
      File.symlink(root, File.join(directory, "alias.y"))
      assert_symlink_cycle(root)

      outside_directory = Dir.mktmpdir("ibex-outside")
      begin
        outside = write(outside_directory, "outside.y", "fragment\nrule\noutside: A\nend\n")
        File.unlink(File.join(directory, "alias.y"))
        File.symlink(outside, File.join(directory, "alias.y"))
        error = assert_raises(Ibex::Error) { resolve(root) }
        assert_match(/resolves outside the root grammar directory/, error.message)
      ensure
        FileUtils.remove_entry(outside_directory)
      end
    end
  rescue NotImplementedError, Errno::EACCES
    skip "symlinks are not available"
  end

  def test_include_paths_reject_unsafe_and_missing_targets
    in_directory do |directory|
      outside_directory = Dir.mktmpdir("ibex-outside")
      begin
        outside = write(outside_directory, "outside.y", "fragment\nrule\noutside: A\nend\n")
        FileUtils.mkdir_p(File.join(directory, "folder"))
        unsafe_paths(outside).each do |path, message|
          error = assert_raises(Ibex::Error) { resolve(write_root_with_include(directory, path)) }
          assert_match message, error.message
        end
      ensure
        FileUtils.remove_entry(outside_directory)
      end
    end
  end

  def test_canonical_ancestry_handles_filesystem_root_and_similar_prefixes
    resolver = Ibex::Frontend::Resolver.new("unused.y", mode: :extended)
    resolver.instance_variable_set(:@root_directory, File::SEPARATOR)
    assert resolver.send(:inside_root?, File.join(File::SEPARATOR, "fragment.y"))

    root = File.join(File::SEPARATOR, "workspace", "grammar")
    resolver.instance_variable_set(:@root_directory, root)
    assert resolver.send(:inside_root?, File.join(root, "nested", "fragment.y"))
    refute resolver.send(:inside_root?, File.join("#{root}-other", "fragment.y"))
  end

  private

  def assert_symlink_cycle(root)
    error = assert_raises(Ibex::Error) { resolve(root) }
    canonical = File.realpath(root)
    assert_equal "#{canonical}:2:1: include cycle: #{canonical} -> #{canonical}", error.message
  end

  def unsafe_paths(outside)
    {
      "../outside.y" => /parent traversal/,
      outside => /must be relative/,
      "*.y" => /glob metacharacters/,
      "bad\u0000.y" => /must not contain NUL/,
      "missing.y" => /does not exist/,
      "folder" => /not a file/
    }
  end

  def in_directory(&block)
    Dir.mktmpdir("ibex-resolver-security", &block)
  end

  def write(directory, relative, content)
    path = File.join(directory, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, content)
    path
  end

  def write_root_with_include(directory, path)
    write(directory, "root.y", "class P\ninclude #{path.dump}\nrule\nstart: TOKEN\nend\n")
  end

  def resolve(path)
    Ibex::Frontend::Resolver.new(path, mode: :extended).resolve
  end
end
