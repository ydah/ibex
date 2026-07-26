# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/lsp"
require "fileutils"
require "tmpdir"

class LSPWorkspaceTest < Minitest::Test
  def test_accepts_local_file_uris_and_new_overlay_paths
    Dir.mktmpdir("ibex-lsp-workspace") do |directory|
      loader = Ibex::Frontend::SourceLoader.new
      workspace = Ibex::LSP::Workspace.new([file_uri(directory)], loader)
      path = File.join(directory, "new grammar.y")
      loader.set_overlay(path, "fragment\nrule\nitem: TOKEN\nend\n")

      canonical = loader.canonical_path(path, allow_missing: true)
      assert_equal canonical, workspace.path(file_uri(path))
      assert_equal file_uri(canonical), workspace.uri(path)
    end
  end

  def test_rejects_non_file_and_outside_uris
    Dir.mktmpdir("ibex-lsp-workspace") do |directory|
      workspace = Ibex::LSP::Workspace.new(
        [file_uri(directory)], Ibex::Frontend::SourceLoader.new
      )

      assert_raises(Ibex::LSP::ProtocolError) { workspace.path("https://example.test/a.y") }
      assert_raises(Ibex::LSP::ProtocolError) { workspace.path(file_uri(File.dirname(directory))) }
      assert_raises(Ibex::LSP::ProtocolError) { workspace.path("#{file_uri(directory)}?query=1") }
      assert_raises(Ibex::LSP::ProtocolError) { workspace.path("#{file_uri(directory)}#fragment") }
      assert_raises(Ibex::LSP::ProtocolError) { workspace.path("file://remote.test#{directory}/a.y") }
      assert_raises(Ibex::LSP::ProtocolError) { workspace.path("file://user@localhost#{directory}/a.y") }
      assert_raises(Ibex::LSP::ProtocolError) { workspace.path("file://localhost:123#{directory}/a.y") }
    end
  end

  def test_decodes_once_preserves_plus_and_rejects_ambiguous_escapes
    Dir.mktmpdir("ibex-lsp-workspace") do |directory|
      loader = Ibex::Frontend::SourceLoader.new
      workspace = Ibex::LSP::Workspace.new([file_uri(directory)], loader)
      plus_path = File.join(directory, "a+b.y")
      loader.set_overlay(plus_path, "fragment\nrule\nitem: TOKEN\nend\n")

      assert_equal loader.canonical_path(plus_path), workspace.path("file://#{plus_path}")
      %w[%2e%2e %2Foutside.y %5Coutside.y %00outside.y %FF %ZZ].each do |suffix|
        uri = "file://#{directory}/#{suffix}"
        assert_raises(Ibex::LSP::ProtocolError, uri) { workspace.path(uri) }
      end
      traversal_back_inside = "file://#{directory}/nested/%2e%2e/a+b.y"
      assert_raises(Ibex::LSP::ProtocolError, traversal_back_inside) do
        workspace.path(traversal_back_inside)
      end
    end
  end

  def test_symlink_paths_cannot_escape_workspace
    Dir.mktmpdir("ibex-lsp-workspace") do |directory|
      outside = Dir.mktmpdir("ibex-lsp-outside")
      begin
        File.symlink(outside, File.join(directory, "link"))
        workspace = Ibex::LSP::Workspace.new(
          [file_uri(directory)], Ibex::Frontend::SourceLoader.new
        )

        error = assert_raises(Ibex::LSP::ProtocolError) do
          workspace.path(file_uri(File.join(directory, "link", "new.y")))
        end
        assert_match(/outside initialized workspace/, error.message)
      ensure
        FileUtils.remove_entry(outside)
      end
    end
  rescue NotImplementedError, Errno::EACCES
    skip "symlinks are not available"
  end

  private

  def file_uri(path)
    "file://#{TestURI::PARSER.escape(path)}"
  end
end
