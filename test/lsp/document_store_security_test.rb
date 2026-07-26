# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/lsp"
require "tmpdir"

class LSPDocumentStoreSecurityTest < Minitest::Test
  def test_dangling_symlink_overlay_is_rejected_before_an_outside_target_can_appear
    with_directories do |workspace_directory, outside_directory|
      target = File.join(outside_directory, "secret.y")
      link = File.join(workspace_directory, "link.y")
      File.symlink(target, link)
      store = build_store(workspace_directory)

      assert_raises(Ibex::LSP::ProtocolError) { store.open(file_uri(link), 1, overlay_source) }
      File.binwrite(target, outside_source)
      assert_raises(Ibex::LSP::ProtocolError) { store.close(file_uri(link)) }
      assert_nil store.snapshot_for(File.realpath(target))
    end
  rescue NotImplementedError, Errno::EACCES
    skip "symlinks are not available"
  end

  def test_close_revalidates_a_new_file_replaced_by_an_outside_symlink
    with_directories do |workspace_directory, outside_directory|
      target = File.join(outside_directory, "secret.y")
      File.binwrite(target, outside_source)
      path = File.join(workspace_directory, "new.y")
      uri = file_uri(path)
      store = build_store(workspace_directory)
      store.open(uri, 1, overlay_source)
      canonical = store.workspace.path(uri)
      File.symlink(target, path)

      assert_raises(Ibex::LSP::ProtocolError) { store.close(uri) }
      snapshot = store.snapshot_for(canonical)
      assert snapshot.fetch(:open)
      assert_equal overlay_source, snapshot.fetch(:source)
      assert store.loader.overlay?(canonical)
    end
  rescue NotImplementedError, Errno::EACCES
    skip "symlinks are not available"
  end

  private

  def with_directories
    Dir.mktmpdir("ibex-lsp-workspace") do |workspace_directory|
      Dir.mktmpdir("ibex-lsp-outside") do |outside_directory|
        yield workspace_directory, outside_directory
      end
    end
  end

  def build_store(directory)
    loader = Ibex::Frontend::SourceLoader.new
    workspace = Ibex::LSP::Workspace.new([file_uri(directory)], loader)
    Ibex::LSP::DocumentStore.new(workspace, loader)
  end

  def file_uri(path)
    "file://#{TestURI::PARSER.escape(path)}"
  end

  def overlay_source
    "class Overlay\nrule\nstart: TOKEN\nend\n"
  end

  def outside_source
    "class Secret\nrule\nstart: LEAK\nend\n"
  end
end
