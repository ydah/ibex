# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/lsp"
require "fileutils"
require "tmpdir"

class LSPDocumentStoreTest < Minitest::Test
  def test_versions_diagnostics_and_close_clear_before_disk_snapshot
    with_store do |store, directory|
      path = write(directory, "root.y", valid_root)
      uri = file_uri(path)

      opened = store.open(uri, 1, valid_root)
      assert_publication(opened, uri, version: 1, diagnostic_count: 0)

      changed = store.change(uri, 2, "class P\nrule\nstart: (\nend\n")
      assert_publication(changed, uri, version: 2, diagnostic_count: 2)
      assert_raises(Ibex::LSP::ProtocolError) { store.change(uri, 2, valid_root) }

      closed = store.close(uri)
      assert_equal({ uri: uri, diagnostics: [] }, closed.first)
      assert_publication(closed.drop(1), uri, version: nil, diagnostic_count: 0)
      refute store.snapshot_for(store.workspace.path(uri)).fetch(:open)
    end
  end

  def test_fragment_overlay_rediagnoses_reverse_dependent_root
    with_store do |store, directory|
      root = write(directory, "root.y", included_root("part.y", "helper"))
      part = write(directory, "part.y", valid_fragment("helper"))
      root_uri = file_uri(root)
      part_uri = file_uri(part)
      store.open(root_uri, 1, File.binread(root))

      broken = store.open(part_uri, 1, "fragment\nrule\nhelper: (\nend\n")
      root_published = broken.any? { |entry| entry.fetch(:uri) == root_uri }
      assert root_published
      assert_publication(broken, part_uri, version: 1, diagnostic_count: 1)

      repaired = store.change(part_uri, 2, valid_fragment("helper"))
      assert_publication(repaired, part_uri, version: 2, diagnostic_count: 0)
      assert_publication(repaired, root_uri, version: 1, diagnostic_count: 0)
    end
  end

  def test_root_diagnostics_reuse_bounded_frontend_recovery
    with_store do |store, directory|
      path = write(directory, "root.y", valid_root)
      source = <<~GRAMMAR
        class P
        expect nope
        token GOOD
        rule
        broken: A | ) | B
        later: GOOD
        end
      GRAMMAR

      publications = store.open(file_uri(path), 1, source)
      publication = publications.reverse.find { |entry| entry.fetch(:uri) == file_uri(path) }

      assert_equal 2, publication.fetch(:diagnostics).length
      lines = publication.fetch(:diagnostics).map { |entry| entry.dig("range", "start", "line") }
      assert_equal [1, 4], lines
    end
  end

  def test_fragment_detection_survives_a_later_lexical_error
    with_store do |store, directory|
      root = write(directory, "root.y", included_root("part.y", "helper"))
      part = write(directory, "part.y", valid_fragment("helper"))
      store.open(file_uri(root), 1, File.binread(root))

      publications = store.open(file_uri(part), 1, "fragment\n@\nrule\nhelper: TOKEN\nend\n")
      publication = publications.reverse.find { |entry| entry.fetch(:uri) == file_uri(part) }
      diagnostic = publication.fetch(:diagnostics).fetch(0)

      assert_equal 1, diagnostic.dig("range", "start", "line")
      assert_match(/unexpected character/, diagnostic.fetch("message"))
      refute_match(/fragment input requires/, diagnostic.fetch("message"))
    end
  end

  def test_new_overlay_satisfies_a_previously_missing_include
    with_store do |store, directory|
      root = write(directory, "root.y", included_root("new.y", "fresh"))
      root_uri = file_uri(root)
      new_path = File.join(directory, "new.y")
      new_uri = file_uri(new_path)

      missing = store.open(root_uri, 1, File.binread(root))
      assert_publication(missing, root_uri, version: 1, diagnostic_count: 1)

      created = store.open(new_uri, 1, valid_fragment("fresh"))
      assert_publication(created, root_uri, version: 1, diagnostic_count: 0)
      assert_publication(created, new_uri, version: 1, diagnostic_count: 0)
    end
  end

  def test_analysis_never_executes_actions_or_user_code
    with_store do |store, directory|
      sentinel = File.join(directory, "executed")
      source = <<~GRAMMAR
        class P
        rule
        start: TOKEN { File.write(#{sentinel.dump}, "action") }
        end
        ---- footer
        File.write(#{sentinel.dump}, "footer")
      GRAMMAR
      path = write(directory, "root.y", source)

      store.open(file_uri(path), 1, source)

      refute_path_exists sentinel
    end
  end

  def test_rejects_oversized_documents_before_installing_an_overlay
    with_store do |store, directory|
      path = File.join(directory, "large.y")
      source = "x" * (Ibex::LSP::Limits::MAX_DOCUMENT_BYTES + 1)

      error = assert_raises(Ibex::LSP::ProtocolError) { store.open(file_uri(path), 1, source) }

      assert_match(/document exceeds/, error.message)
      refute store.loader.overlay?(path)
    end
  end

  def test_root_membership_is_removed_for_fragment_invalid_and_close_and_reopen_resets_version_epoch
    with_store do |store, directory|
      path = write(directory, "root.y", valid_root)
      uri = file_uri(path)
      canonical = store.workspace.path(uri)
      store.open(uri, 9, valid_root)
      assert_equal [canonical], store.roots_for(canonical)

      store.change(uri, 10, valid_fragment("helper"))
      assert_empty store.roots_for(canonical)
      store.change(uri, 11, "not a grammar")
      assert_empty store.roots_for(canonical)
      store.change(uri, 12, valid_root)
      assert_equal [canonical], store.roots_for(canonical)

      store.close(uri)
      assert_empty store.roots_for(canonical)
      store.open(uri, 0, valid_root)
      assert_equal 0, store.snapshot_for(canonical).fetch(:version)
    end
  end

  def test_shared_fragment_keeps_every_reverse_dependent_root
    with_store do |store, directory|
      shared = write(directory, "shared.y", valid_fragment("helper"))
      first = write(directory, "first.y", included_root("shared.y", "helper"))
      second = write(directory, "second.y", included_root("shared.y", "helper"))
      store.open(file_uri(first), 1, File.binread(first))
      store.open(file_uri(second), 1, File.binread(second))
      shared_path = store.workspace.path(file_uri(shared))

      roots = store.roots_for(shared_path)
      assert_equal [first, second].map { |path| File.realpath(path) }.sort, roots.sort

      publications = store.open(file_uri(shared), 1, "fragment\nrule\nhelper: (\nend\n")
      published = publications.map { |entry| entry.fetch(:uri) }
      assert_includes published, file_uri(first)
      assert_includes published, file_uri(second)
    end
  end

  def test_open_document_notifications_require_the_original_uri_alias
    with_store do |store, directory|
      source = valid_root
      real = write(directory, "real.y", source)
      first_alias = File.join(directory, "first-alias.y")
      second_alias = File.join(directory, "second-alias.y")
      File.symlink(real, first_alias)
      File.symlink(real, second_alias)
      store.open(file_uri(first_alias), 7, source)

      assert_raises(Ibex::LSP::ProtocolError) { store.change(file_uri(real), 8, source) }
      assert_raises(Ibex::LSP::ProtocolError) { store.save(file_uri(second_alias), source: source) }
      assert_raises(Ibex::LSP::ProtocolError) { store.close(file_uri(real)) }

      store.change(file_uri(first_alias), 8, source)
      store.close(file_uri(first_alias))
    end
  rescue NotImplementedError, Errno::EACCES
    skip "symlinks are not available"
  end

  private

  def with_store
    Dir.mktmpdir("ibex-lsp-store") do |directory|
      loader = Ibex::Frontend::SourceLoader.new
      workspace = Ibex::LSP::Workspace.new([file_uri(directory)], loader)
      yield Ibex::LSP::DocumentStore.new(workspace, loader), directory
    end
  end

  def write(directory, relative, source)
    path = File.join(directory, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, source)
    path
  end

  def file_uri(path)
    "file://#{TestURI::PARSER.escape(path)}"
  end

  def valid_root
    "class P\nrule\nstart: TOKEN\nend\n"
  end

  def valid_fragment(name)
    "fragment\nrule\n#{name}: TOKEN\nend\n"
  end

  def included_root(path, name)
    "class P\ninclude #{path.dump}\nrule\nstart: #{name}\nend\n"
  end

  def assert_publication(publications, uri, version:, diagnostic_count:)
    publication = publications.reverse.find { |entry| entry.fetch(:uri) == uri }
    refute_nil publication
    version ? assert_equal(version, publication[:version]) : assert_nil(publication[:version])
    assert_equal diagnostic_count, publication.fetch(:diagnostics).length
  end
end
