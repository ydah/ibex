# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/lsp"
require "fileutils"
require "tmpdir"

class LSPSymbolIndexTest < Minitest::Test
  def test_cross_file_definition_references_formal_scope_and_include_target
    with_index do |index, store, paths|
      root = paths.fetch(:root)
      part = paths.fetch(:part)

      pair_definition = index.definition(root, position(store, root, "pair(TOKEN)"))
      assert_equal file_uri(part), pair_definition.fetch(0).fetch("uri")

      helper_references = index.references(part, position(store, part, "helper: TOKEN"), include_declaration: true)
      assert_equal 2, helper_references.length
      all_in_part = helper_references.all? { |location| location.fetch("uri") == file_uri(part) }
      assert all_in_part

      parameter_definition = index.definition(part, position(store, part, "X helper", offset: 0))
      assert_equal 1, parameter_definition.length
      assert_equal file_uri(part), parameter_definition.fetch(0).fetch("uri")

      include_definition = index.definition(root, position(store, root, "\"part.y\"", offset: 2))
      assert_equal file_uri(part), include_definition.fetch(0).fetch("uri")
    end
  end

  def test_prepare_rename_and_validated_workspace_edit
    with_index do |index, store, paths|
      root = paths.fetch(:root)
      part = paths.fetch(:part)
      token_position = position(store, root, "TOKEN", offset: 1)

      prepared = index.prepare_rename(root, token_position)
      assert_equal "TOKEN", prepared.fetch("placeholder")

      edit = index.rename(root, token_position, "LEXEME")
      changes = edit.fetch("documentChanges")
      changed_uris = changes.map { |change| change.dig("textDocument", "uri") }
      assert_includes changed_uris, store.uri_for(root)
      assert_includes changed_uris, store.uri_for(part)
      all_renamed = changes.flat_map { |change| change.fetch("edits") }
                           .all? { |entry| entry.fetch("newText") == "LEXEME" }
      assert all_renamed

      collision = assert_raises(Ibex::LSP::ProtocolError) do
        index.rename(part, position(store, part, "pair(X)"), "helper")
      end
      assert_match(/collides/, collision.message)

      store.stub(:valid_replacements?, false) do
        error = assert_raises(Ibex::LSP::ProtocolError) do
          index.rename(part, position(store, part, "helper: TOKEN"), "renamed")
        end
        assert_match(/closure invalid/, error.message)
      end
    end
  end

  def test_hover_describes_rules_terminals_and_includes
    with_index do |index, store, paths|
      root = paths.fetch(:root)
      part = paths.fetch(:part)

      rule_hover = index.hover(root, position(store, root, "pair(TOKEN)"))
      rule_text = rule_hover.dig("contents", "value")
      assert_includes rule_text, "%inline pair(X)"
      assert_includes rule_text, "Pair documentation."

      terminal_hover = index.hover(part, position(store, part, "TOKEN"))
      terminal_text = terminal_hover.dig("contents", "value")
      assert_includes terminal_text, "token display"
      assert_includes terminal_text, "String"
      assert_includes terminal_text, "left"

      include_hover = index.hover(root, position(store, root, "\"part.y\"", offset: 2))
      assert_includes include_hover.dig("contents", "value"), File.realpath(part)
    end
  end

  def test_indexes_terminal_metadata_precedence_convert_and_start_occurrences_without_opaque_text
    with_index do |index, store, paths|
      root = paths.fetch(:root)

      token_references = index.references(
        root, position(store, root, "token TOKEN", offset: 7), include_declaration: true
      )
      assert_equal 7, token_references.length

      start_references = index.references(
        root, position(store, root, "start start", offset: 6), include_declaration: true
      )
      assert_equal 2, start_references.length

      edit = index.rename(root, position(store, root, "token TOKEN", offset: 7), "LEXEME")
      edit_count = edit.fetch("documentChanges").sum { |change| change.fetch("edits").length }
      assert_equal 7, edit_count
    end
  end

  def test_rename_from_a_fragment_shared_by_multiple_roots_is_rejected
    Dir.mktmpdir("ibex-lsp-symbol") do |directory|
      shared = write(directory, "shared.y", "fragment\nrule\nhelper: TOKEN\nend\n")
      first = write(directory, "first.y", "class A\ninclude \"shared.y\"\nrule\nstart: helper\nend\n")
      second = write(directory, "second.y", "class B\ninclude \"shared.y\"\nrule\nstart: helper\nend\n")
      loader = Ibex::Frontend::SourceLoader.new
      workspace = Ibex::LSP::Workspace.new([file_uri(directory)], loader)
      store = Ibex::LSP::DocumentStore.new(workspace, loader)
      store.open(file_uri(first), 1, File.binread(first))
      store.open(file_uri(second), 1, File.binread(second))
      store.open(file_uri(shared), 1, File.binread(shared))
      canonical_first = workspace.path(file_uri(first))
      canonical_shared = workspace.path(file_uri(shared))

      index = Ibex::LSP::SymbolIndex.new(store, canonical_first)
      error = assert_raises(Ibex::LSP::ProtocolError) do
        index.rename(canonical_first, position(store, canonical_first, "helper"), "renamed")
      end
      assert_match(/multiple roots is ambiguous/, error.message)

      index = Ibex::LSP::SymbolIndex.new(store, canonical_shared)
      error = assert_raises(Ibex::LSP::ProtocolError) do
        index.rename(canonical_shared, position(store, canonical_shared, "helper:"), "renamed")
      end
      assert_match(/multiple roots is ambiguous/, error.message)
    end
  end

  def test_quoted_and_reserved_symbols_cannot_be_renamed
    Dir.mktmpdir("ibex-lsp-symbol") do |directory|
      source = "class P\ntoken '+'\nrule\nstart: '+'\nend\n"
      root = write(directory, "root.y", source)
      store = open_store(directory, root, source)
      root = store.workspace.path(file_uri(root))
      index = Ibex::LSP::SymbolIndex.new(store, root)

      assert_raises(Ibex::LSP::ProtocolError) do
        index.prepare_rename(root, position(store, root, "'+'", offset: 1))
      end
      assert_raises(Ibex::LSP::ProtocolError) do
        index.rename(root, position(store, root, "start:"), "end")
      end
    end
  end

  private

  def with_index
    Dir.mktmpdir("ibex-lsp-symbol") do |directory|
      part = write(directory, "part.y", fragment_source)
      root = write(directory, "root.y", root_source)
      store = open_store(directory, root, root_source)
      canonical_root = store.workspace.path(file_uri(root))
      canonical_part = store.workspace.path(file_uri(part))
      yield Ibex::LSP::SymbolIndex.new(store, canonical_root), store,
            { root: canonical_root, part: canonical_part }
    end
  end

  def open_store(directory, root, source)
    loader = Ibex::Frontend::SourceLoader.new
    workspace = Ibex::LSP::Workspace.new([file_uri(directory)], loader)
    store = Ibex::LSP::DocumentStore.new(workspace, loader)
    store.open(file_uri(root), 1, source)
    store
  end

  def write(directory, relative, source)
    path = File.join(directory, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, source)
    path
  end

  def position(store, path, needle, offset: 0)
    source = store.snapshot_for(path).fetch(:source)
    byte = source.b.index(needle.b)
    refute_nil byte
    Ibex::LSP::PositionCodec.new(source).position(byte + offset)
  end

  def file_uri(path)
    "file://#{TestURI::PARSER.escape(path)}"
  end

  def root_source
    <<~GRAMMAR
      class P
      pragma extended
      include "part.y"
      token TOKEN
      start start
      convert
      TOKEN 'Integer(_1)'
      end
      display TOKEN "token display"
      type TOKEN "String"
      prechigh
      left TOKEN
      preclow
      rule
      # TOKEN in a comment is not a symbol occurrence.
      start: pair(TOKEN) { result = "TOKEN" }
      end
    GRAMMAR
  end

  def fragment_source
    <<~GRAMMAR
      fragment
      rule
      ## Pair documentation.
      %inline pair(X): X helper
      helper: TOKEN
      end
    GRAMMAR
  end
end
