# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/lsp"
require "fileutils"
require "tmpdir"

class LSPSymbolIndexRegressionTest < Minitest::Test
  def test_indexes_terminal_and_formal_alternative_precedence_references
    with_precedence_index do |index, store, root|
      terminal_references = index.references(
        root, position(store, root, "token TOKEN UMINUS", 12), include_declaration: true
      )
      assert_equal 3, terminal_references.length
      terminal_edit = index.rename(root, position(store, root, "token TOKEN UMINUS", 12), "PREFIX")
      assert_equal 3, edit_count(terminal_edit)

      index = Ibex::LSP::SymbolIndex.new(store, root)
      formal_references = index.references(
        root, position(store, root, "expression(X)", 11), include_declaration: true
      )
      assert_equal 3, formal_references.length
      formal_edit = index.rename(root, position(store, root, "expression(X)", 11), "VALUE")
      assert_equal 3, edit_count(formal_edit)
    end
  end

  def test_open_alias_uri_is_used_for_definition_references_and_include_target
    with_alias_index do |index, store, root, aliases|
      definition = index.definition(root, position(store, root, "start: helper", 7))
      assert_equal aliases.fetch(:part), definition.fetch(0).fetch("uri")
      include_target = index.definition(root, position(store, root, "\"part-alias.y\"", 2))
      assert_equal aliases.fetch(:part), include_target.fetch(0).fetch("uri")

      references = index.references(root, position(store, root, "token TOKEN", 6), include_declaration: true)
      reference_uris = references.map { |entry| entry.fetch("uri") }.uniq.sort
      assert_equal aliases.values.sort, reference_uris
    end
  rescue NotImplementedError, Errno::EACCES
    skip "symlinks are not available"
  end

  def test_closed_alias_target_falls_back_to_its_canonical_uri
    with_alias_index do |_index, store, root, aliases|
      store.close(aliases.fetch(:part))
      index = Ibex::LSP::SymbolIndex.new(store, root)

      include_target = index.definition(root, position(store, root, "\"part-alias.y\"", 2))
      target = store.workspace.path(aliases.fetch(:part))
      assert_equal store.workspace.uri(target), include_target.fetch(0).fetch("uri")
    end
  rescue NotImplementedError, Errno::EACCES
    skip "symlinks are not available"
  end

  def test_open_alias_uri_and_version_are_used_for_rename_edits
    with_alias_index do |index, store, root, aliases|
      edit = index.rename(root, position(store, root, "token TOKEN", 6), "LEXEME")
      text_documents = edit.fetch("documentChanges").to_h do |change|
        document = change.fetch("textDocument")
        [document.fetch("uri"), document.fetch("version")]
      end

      assert_equal({ aliases.fetch(:root) => 7, aliases.fetch(:part) => 9 }, text_documents)
    end
  rescue NotImplementedError, Errno::EACCES
    skip "symlinks are not available"
  end

  private

  def with_precedence_index
    Dir.mktmpdir("ibex-lsp-precedence") do |directory|
      root = write(directory, "root.y", precedence_source)
      store = open_store(directory, root, precedence_source)
      root = store.workspace.path(file_uri(root))
      yield Ibex::LSP::SymbolIndex.new(store, root), store, root
    end
  end

  def with_alias_index
    Dir.mktmpdir("ibex-lsp-alias") do |directory|
      root_alias, part_alias = write_alias_closure(directory)
      store = open_store(directory, root_alias, root_source)
      store.open(file_uri(part_alias), 9, part_source)
      root = store.workspace.path(file_uri(root_alias))
      aliases = { root: file_uri(root_alias), part: file_uri(part_alias) }
      yield Ibex::LSP::SymbolIndex.new(store, root), store, root, aliases
    end
  end

  def open_store(directory, root, source)
    loader = Ibex::Frontend::SourceLoader.new
    workspace = Ibex::LSP::Workspace.new([file_uri(directory)], loader)
    store = Ibex::LSP::DocumentStore.new(workspace, loader)
    store.open(file_uri(root), 7, source)
    store
  end

  def write_alias_closure(directory)
    real = write(directory, "real.y", root_source)
    part_real = write(directory, "part-real.y", part_source)
    root_alias = File.join(directory, "alias.y")
    part_alias = File.join(directory, "part-alias.y")
    File.symlink(real, root_alias)
    File.symlink(part_real, part_alias)
    [root_alias, part_alias]
  end

  def write(directory, relative, source)
    path = File.join(directory, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, source)
    path
  end

  def position(store, path, needle, offset)
    byte = store.snapshot_for(path).fetch(:source).b.index(needle.b)
    refute_nil byte
    Ibex::LSP::PositionCodec.new(store.snapshot_for(path).fetch(:source)).position(byte + offset)
  end

  def edit_count(edit)
    edit.fetch("documentChanges").sum { |change| change.fetch("edits").length }
  end

  def file_uri(path)
    "file://#{TestURI::PARSER.escape(path)}"
  end

  def precedence_source
    <<~GRAMMAR
      class P
      pragma extended
      token TOKEN UMINUS
      prechigh
      left UMINUS
      preclow
      rule
      expression(X): X = X
      unary: TOKEN = UMINUS
      end
    GRAMMAR
  end

  def root_source
    "class P\ninclude \"part-alias.y\"\ntoken TOKEN\nrule\nstart: helper TOKEN\nend\n"
  end

  def part_source
    "fragment\nrule\nhelper: TOKEN\nend\n"
  end
end
