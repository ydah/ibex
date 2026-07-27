# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "tmpdir"

class FrontendImportTest < Minitest::Test
  def test_import_is_extended
    source = "class P\nimport \"fragment.y\"\nrule\nstart: TOKEN\nend\n"
    generated = parse(source, mode: :extended)

    assert_equal "fragment.y", generated.declarations.fetch(0).path

    error = assert_raises(Ibex::Error) { parse(source) }
    assert_equal "grammar.y:2:1: imports require extended mode", error.message
  end

  def test_import_merges_token_sets_and_deduplicates_a_diamond
    Dir.mktmpdir("ibex-import") do |directory|
      paths = write_import_graph(directory)
      resolution = Ibex::Frontend::Resolver.new(paths.fetch(:root), mode: :extended).resolve
      grammar = Ibex::Normalizer.new(resolution, mode: :extended).normalize

      expected = %i[root first shared second].map { |key| File.realpath(paths.fetch(key)) }
      shared_rule_count = resolution.root.rules.count { |rule| rule.lhs == "shared" }
      assert_equal expected, resolution.files
      assert_equal 1, shared_rule_count
      %w[FROM_A FROM_B SHARED].each do |token|
        assert_equal :terminal, grammar.symbol(token).kind
      end
    end
  end

  private

  def parse(source, mode: :default)
    Ibex::Frontend::Parser.new(source, file: "grammar.y", mode: mode).parse
  end

  def write_import_graph(directory)
    {
      root: write(directory, "root.y",
                  "class P\nimport \"a.y\"\nimport \"b.y\"\nrule\nstart: from_a from_b shared\nend\n"),
      first: write(directory, "a.y",
                   "fragment\ntoken FROM_A\nimport \"shared.y\"\nrule\nfrom_a: FROM_A\nend\n"),
      second: write(directory, "b.y",
                    "fragment\ntoken FROM_B\nimport \"shared.y\"\nrule\nfrom_b: FROM_B\nend\n"),
      shared: write(directory, "shared.y",
                    "fragment\ntoken SHARED\nrule\nshared: SHARED\nend\n")
    }
  end

  def write(directory, name, source)
    path = File.join(directory, name)
    File.binwrite(path, source)
    path
  end
end
