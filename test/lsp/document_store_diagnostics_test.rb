# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/lsp"
require "fileutils"
require "tmpdir"

class LSPDocumentStoreDiagnosticsTest < Minitest::Test
  def test_shared_fragment_diagnostics_survive_closing_one_root
    with_store do |store, directory|
      shared, first, second = write_shared_closure(directory)
      store.open(file_uri(first), 1, File.binread(first))
      store.open(file_uri(second), 1, File.binread(second))
      shared_uri = store.workspace.uri(store.workspace.path(file_uri(shared)))

      publications = store.close(file_uri(first))

      assert_diagnostic_count(publications, shared_uri, 1)
    end
  end

  def test_shared_fragment_diagnostics_survive_other_root_refresh_and_qualification_loss
    with_store do |store, directory|
      shared, first, second = write_shared_closure(directory)
      store.open(file_uri(first), 1, File.binread(first))
      store.open(file_uri(second), 1, File.binread(second))
      shared_uri = store.workspace.uri(store.workspace.path(file_uri(shared)))

      refreshed = store.change(file_uri(first), 2, valid_root)
      assert_diagnostic_count(refreshed, shared_uri, 1)

      store.change(file_uri(first), 3, included_root)
      disqualified = store.change(file_uri(first), 4, valid_fragment)
      assert_diagnostic_count(disqualified, shared_uri, 1)
    end
  end

  private

  def with_store
    Dir.mktmpdir("ibex-lsp-diagnostics") do |directory|
      loader = Ibex::Frontend::SourceLoader.new
      workspace = Ibex::LSP::Workspace.new([file_uri(directory)], loader)
      yield Ibex::LSP::DocumentStore.new(workspace, loader), directory
    end
  end

  def write_shared_closure(directory)
    shared = write(directory, "shared.y", "fragment\nrule\nhelper: (\nend\n")
    first = write(directory, "first.y", included_root)
    second = write(directory, "second.y", included_root)
    [shared, first, second]
  end

  def write(directory, relative, source)
    path = File.join(directory, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, source)
    path
  end

  def file_uri(path)
    "file://#{URI::RFC2396_PARSER.escape(path)}"
  end

  def included_root
    "class P\ninclude \"shared.y\"\nrule\nstart: helper\nend\n"
  end

  def valid_root
    "class P\nrule\nstart: TOKEN\nend\n"
  end

  def valid_fragment
    "fragment\nrule\nstandalone: TOKEN\nend\n"
  end

  def assert_diagnostic_count(publications, uri, count)
    publication = publications.reverse.find { |entry| entry.fetch(:uri) == uri }
    refute_nil publication
    assert_equal count, publication.fetch(:diagnostics).length
  end
end
