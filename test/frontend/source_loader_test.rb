# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "tmpdir"

class FrontendSourceLoaderTest < Minitest::Test
  def test_disk_loader_preserves_resolver_behavior
    Dir.mktmpdir("ibex-source-loader") do |directory|
      root = write(directory, "root.y", "class P\ninclude \"part.y\"\nrule\nstart: helper\nend\n")
      part = write(directory, "part.y", "fragment\nrule\nhelper: TOKEN\nend\n")

      resolution = Ibex::Frontend::Resolver.new(root, mode: :extended).resolve

      assert_equal [File.realpath(root), File.realpath(part)], resolution.files
      assert_equal %w[helper start], resolution.root.rules.map(&:lhs)
    end
  end

  def test_overlay_wins_for_root_included_and_new_files
    Dir.mktmpdir("ibex-source-loader") do |directory|
      root = write(directory, "root.y", "class P\ninclude \"part.y\"\nrule\nstart: disk\nend\n")
      part = write(directory, "part.y", "fragment\nrule\ndisk: TOKEN\nend\n")
      new_part = File.join(directory, "new.y")
      loader = Ibex::Frontend::SourceLoader.new
      loader.set_overlay(root, "class P\ninclude \"part.y\"\ninclude \"new.y\"\nrule\nstart: edited fresh\nend\n")
      loader.set_overlay(part, "fragment\nrule\nedited: TOKEN\nend\n")
      loader.set_overlay(new_part, "fragment\nrule\nfresh: TOKEN\nend\n")

      resolution = Ibex::Frontend::Resolver.new(root, mode: :extended, loader: loader).resolve

      assert_equal %w[edited fresh start], resolution.root.rules.map(&:lhs)
      assert_equal [root, part, new_part].map { |path| File.realpath(File.dirname(path)) + "/#{File.basename(path)}" },
                   resolution.files
      assert_equal "fragment\nrule\ndisk: TOKEN\nend\n", loader.disk_source(part)
    end
  end

  def test_overlay_canonicalization_observes_symlink_escape
    Dir.mktmpdir("ibex-source-loader") do |directory|
      outside = Dir.mktmpdir("ibex-source-loader-outside")
      begin
        root = write(directory, "root.y", "class P\ninclude \"link/new.y\"\nrule\nstart: fresh\nend\n")
        File.symlink(outside, File.join(directory, "link"))
        loader = Ibex::Frontend::SourceLoader.new
        escaped = File.join(directory, "link", "new.y")
        loader.set_overlay(escaped, "fragment\nrule\nfresh: TOKEN\nend\n")

        error = assert_raises(Ibex::Error) do
          Ibex::Frontend::Resolver.new(root, mode: :extended, loader: loader).resolve
        end

        assert_match(/resolves outside the root grammar directory/, error.message)
      ensure
        FileUtils.remove_entry(outside)
      end
    end
  rescue NotImplementedError, Errno::EACCES
    skip "symlinks are not available"
  end

  def test_existing_directory_cannot_be_installed_as_an_overlay
    Dir.mktmpdir("ibex-source-loader") do |directory|
      loader = Ibex::Frontend::SourceLoader.new

      error = assert_raises(ArgumentError) { loader.set_overlay(directory, "fragment\nrule\nend\n") }

      assert_match(/must not be a directory/, error.message)
      refute loader.overlay?(directory)
    end
  end

  private

  def write(directory, relative, source)
    path = File.join(directory, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, source)
    path
  end
end
