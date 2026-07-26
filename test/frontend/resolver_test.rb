# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "tmpdir"

class FrontendResolverTest < Minitest::Test
  def test_parser_keeps_root_and_fragment_contracts_explicit
    source = "fragment\ntoken TOKEN\nrule\nhelper: TOKEN\nend\n"
    parser = Ibex::Frontend::Parser.new(source, file: "fragment.y", mode: :extended)
    fragment = parser.parse_fragment

    assert_instance_of Ibex::Frontend::AST::Fragment, fragment
    assert_equal ["helper"], fragment.rules.map(&:lhs)
    error = assert_raises(Ibex::Error) { parser.parse }
    assert_equal "fragment.y:1:1: fragment input requires Parser#parse_fragment", error.message

    root = Ibex::Frontend::Parser.new("class P\nrule\nstart: TOKEN\nend\n", mode: :extended)
    assert_raises(Ibex::Error) { root.parse_fragment }

    mode_error = assert_raises(Ibex::Error) do
      Ibex::Frontend::Parser.new(source, file: "fragment.y").parse_fragment
    end
    assert_equal "fragment.y:1:1: fragments require extended mode", mode_error.message
  end

  def test_simple_nested_and_diamond_resolution_is_depth_first_and_deduplicated
    in_directory do |directory|
      paths = write_diamond(directory)
      root, a, b, shared = paths.values_at(:root, :a, :b, :shared)

      resolution = resolve(root)

      assert_diamond_files_and_rules(resolution, root, a, b, shared)
      assert_diamond_chains(resolution, a, shared)
    end
  end

  def test_resolution_preserves_root_extended_pragma
    in_directory do |directory|
      root = write(directory, "root.y", "class P\npragma extended\nrule\nstart: TOKEN\nend\n")
      resolution = Ibex::Frontend::Resolver.new(root).resolve

      assert_equal true, resolution.root.extended
      assert_equal :extended, Ibex::Normalizer.new(resolution).normalize.mode
    end
  end

  def test_fragments_reject_root_only_declarations_user_code_and_root_documents
    root_only = {
      "options no_result_var" => "options",
      "expect 1" => "expect",
      "%expect-rr 1" => "%expect-rr",
      "%param context" => "%param",
      "start helper" => "start",
      "%recover sync: TOKEN" => "%recover",
      "%on_error_reduce helper" => "%on_error_reduce",
      "%test accept \"TOKEN\"" => "%test"
    }
    root_only.each do |declaration, label|
      source = "fragment\n#{declaration}\nrule\nhelper: TOKEN\nend\n"
      error = assert_raises(Ibex::Error) do
        Ibex::Frontend::Parser.new(source, file: "#{label}.y", mode: :extended).parse_fragment
      end
      assert_equal "#{label}.y:2:1: #{label} declarations are not allowed in fragments", error.message
    end

    user_code = "fragment\nrule\nend\n---- footer\nVALUE = 1\n"
    error = assert_raises(Ibex::Error) do
      Ibex::Frontend::Parser.new(user_code, file: "code.y", mode: :extended).parse_fragment
    end
    assert_equal "code.y:4:1: user code is not allowed in fragments", error.message

    pragma = "fragment\npragma extended\nrule\nend\n"
    error = assert_raises(Ibex::Error) do
      Ibex::Frontend::Parser.new(pragma, file: "pragma.y", mode: :extended).parse_fragment
    end
    assert_equal "pragma.y:2:1: pragma declarations are not allowed in fragments", error.message
  end

  def test_normalizer_rejects_unresolved_nodes_and_reports_cross_file_duplicates
    in_directory do |directory|
      root, fragment = write_duplicate_fixture(directory)

      unresolved = Ibex::Frontend::Parser.new(File.binread(root), file: root, mode: :extended).parse
      error = assert_raises(Ibex::Error) { Ibex::Normalizer.new(unresolved, mode: :extended).normalize }
      assert_match(/includes must be resolved before normalization/, error.message)

      fragment_ast = Ibex::Frontend::Parser.new(
        File.binread(fragment), file: fragment, mode: :extended
      ).parse_fragment
      error = assert_raises(Ibex::Error) { Ibex::Normalizer.new(fragment_ast, mode: :extended).normalize }
      assert_match(/fragments must be resolved before normalization/, error.message)

      duplicate = assert_raises(Ibex::Error) do
        Ibex::Normalizer.new(resolve(root), mode: :extended).normalize
      end
      assert_equal "#{File.realpath(fragment)}:2:1: duplicate display declaration for TOKEN", duplicate.message
    end
  end

  def test_resolved_ir_has_deterministic_v2_provenance_without_changing_v1_shape
    in_directory do |directory|
      root = write(directory, "root.y", "class P\ninclude \"part.y\"\nrule\nstart: helper\nend\n")
      fragment = write(directory, "part.y", "fragment\nrule\nhelper: TOKEN\nend\n")

      grammars = 2.times.map { Ibex::Normalizer.new(resolve(root), mode: :extended).normalize }
      assert_equal grammars.first.to_h, grammars.last.to_h

      assert_resolved_metadata(grammars.first, root, fragment, directory)
    end
  end

  def test_resolution_deeply_freezes_ast_and_copies_provenance_without_losing_rule_identity
    ast = Ibex::Frontend::Parser.new(
      "class P\nrule\nstart: (TOKEN | OTHER)+\nend\n", file: "root.y", mode: :extended
    ).parse
    rule = ast.rules.fetch(0)
    file = +"fragment.y"
    source_root = +"source"
    span = { start: 4, end: 12 }
    entry = { file: file, root: source_root, byte_span: span }
    chains = {}.compare_by_identity
    chains[rule] = [entry]

    resolution = Ibex::Frontend::Resolution.new(
      root: ast, root_path: "root.y", root_directory: ".", files: ["root.y"], include_chains: chains
    )
    chain = resolution.include_chain_for(rule)

    assert_same rule, resolution.root.rules.fetch(0)
    assert_deeply_frozen resolution.root
    assert_deeply_frozen chain
    file << ".changed"
    source_root << ".changed"
    span[:start] = 99
    assert_equal(
      [{ file: "fragment.y", root: "source", byte_span: { start: 4, end: 12 } }],
      chain
    )
    assert_empty resolution.include_chain_for(rule.dup)
  end

  private

  def in_directory(&block)
    Dir.mktmpdir("ibex-resolver", &block)
  end

  def write(directory, relative, content)
    path = File.join(directory, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, content)
    path
  end

  def write_diamond(directory)
    {
      root: write(directory, "root.y", diamond_root),
      a: write(directory, "a.y", diamond_fragment("shared.y", "from_a")),
      b: write(directory, "b.y", diamond_fragment("shared.y", "from_b")),
      shared: write(directory, "shared.y", "fragment\ntoken TOKEN\nrule\nshared: TOKEN\nend\n")
    }
  end

  def diamond_root
    "class P\ninclude \"a.y\"\ninclude \"b.y\"\nrule\nstart: from_a from_b shared\nend\n"
  end

  def diamond_fragment(include_path, rule)
    "fragment\ninclude \"#{include_path}\"\nrule\n#{rule}: shared\nend\n"
  end

  def write_duplicate_fixture(directory)
    root = write(
      directory, "root.y",
      "class P\ndisplay TOKEN \"root\"\ninclude \"fragment.y\"\nrule\nstart: TOKEN\nend\n"
    )
    fragment = write(
      directory, "fragment.y",
      "fragment\ndisplay TOKEN \"fragment\"\nrule\nhelper: TOKEN\nend\n"
    )
    [root, fragment]
  end

  def assert_resolved_metadata(grammar, root, fragment, directory)
    expected = { file: File.realpath(root), root: File.realpath(directory), byte_span: nil }
    assert_equal expected, grammar.source_provenance
    helper = grammar.productions.find { |production| grammar.symbol_by_id(production.lhs)&.name == "helper" }
    refute_nil helper
    assert_equal File.realpath(fragment), helper.origin.fetch(:loc).fetch(:file)
    chain = helper.expansion.fetch(:include_chain).map { |entry| entry.fetch(:file) }
    assert_equal [File.realpath(fragment)], chain
    assert_nil helper.documentation
    refute_includes helper.to_h(schema_version: 1), :expansion
    refute_includes helper.to_h(schema_version: 1), :doc
  end

  def assert_diamond_files_and_rules(resolution, root, first, second, shared)
    assert_equal [root, first, shared, second].map { |path| File.realpath(path) }, resolution.files
    assert_equal %w[shared from_a from_b start], resolution.root.rules.map(&:lhs)
    shared_count = resolution.root.rules.count { |rule| rule.lhs == "shared" }
    assert_equal 1, shared_count
    assert_equal File.realpath(shared), resolution.root.rules.first.loc.file
  end

  def assert_diamond_chains(resolution, first, shared)
    shared_chain = resolution.include_chain_for(resolution.root.rules.first)
    chain_files = shared_chain.map { |entry| entry.fetch(:file) }
    assert_equal [File.realpath(first), File.realpath(shared)], chain_files
    assert_empty resolution.include_chain_for(resolution.root.rules.last)
  end

  def resolve(path)
    Ibex::Frontend::Resolver.new(path, mode: :extended).resolve
  end

  def assert_deeply_frozen(value)
    assert_predicate value, :frozen?
    case value
    when Struct
      value.each_pair { |_name, child| assert_deeply_frozen(child) }
    when Array
      value.each { |child| assert_deeply_frozen(child) }
    when Hash
      value.each do |key, child|
        assert_deeply_frozen(key)
        assert_deeply_frozen(child)
      end
    end
  end
end
