# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/lsp"
require "tmpdir"

class LSPParserConfigurationAssistanceTest < Minitest::Test
  def test_completion_offers_only_admitted_keys_and_values_inside_a_root_parser_block
    source = "class P\nparser\n  algorithm \nend\nrule\nstart: TOKEN\nend\n"

    with_assistance(source) do |assistance|
      values = assistance.completion("line" => 2, "character" => 12).fetch("items").map { |item| item["label"] }
      assert_equal %w[slr lalr ielr lr1], values

      keys = assistance.completion("line" => 2, "character" => 2).fetch("items").map { |item| item["label"] }
      assert_equal %w[algorithm entries], keys

      outside = assistance.completion("line" => 4, "character" => 0)
      assert_empty outside.fetch("items")
    end
  end

  def test_hover_describes_parser_keys_and_values_without_executing_grammar_code
    source = <<~GRAMMAR
      class P
      parser
        entries isolated
        algorithm ielr
      end
      rule
      start: TOKEN
      end
    GRAMMAR

    with_assistance(source) do |assistance|
      key = assistance.hover("line" => 2, "character" => 4)
      value = assistance.hover("line" => 3, "character" => 14)

      assert_includes key.dig("contents", "value"), "parser.entries"
      assert_includes key.dig("contents", "value"), "shared"
      assert_includes value.dig("contents", "value"), "IELR"
      assert_nil assistance.hover("line" => 6, "character" => 2)
    end
  end

  private

  def with_assistance(source)
    Dir.mktmpdir("ibex-lsp-parser-configuration") do |directory|
      path = File.join(directory, "grammar.y")
      File.binwrite(path, source)
      loader = Ibex::Frontend::SourceLoader.new
      workspace = Ibex::LSP::Workspace.new([file_uri(directory)], loader)
      store = Ibex::LSP::DocumentStore.new(workspace, loader)
      store.open(file_uri(path), 1, source)
      canonical = workspace.path(file_uri(path))
      yield Ibex::LSP::ParserConfigurationAssistance.new(store, canonical)
    end
  end

  def file_uri(path)
    "file://#{TestURI::PARSER.escape(path)}"
  end
end
