# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/frontend/regenerator"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

class FrontendSelfHostTest < Minitest::Test
  FIXTURE = File.expand_path("../fixtures/grammar/comprehensive.y", __dir__)
  EXTENDED_FIXTURES = %w[extended.y edge.y].map do |name|
    File.expand_path("../fixtures/grammar/#{name}", __dir__)
  end.freeze
  GENERATED = File.expand_path("../../lib/ibex/frontend/generated_parser.rb", __dir__)
  GENERATED_SIGNATURE = File.expand_path("../../sig/ibex/frontend/generated_parser.rbs", __dir__)
  ROOT = File.expand_path("../..", __dir__)
  MALFORMED_GRAMMARS = [
    ["class P\ntoken X\n", :racc],
    ["class P\nrule\ns: X\n", :racc],
    ["class P\nprechigh\nmiddle X\npreclow\nrule\ns: X\nend\n", :racc],
    ["class P\nprechigh\nleft X\n", :racc],
    ["class P\nconvert\nX 'x'\n", :racc],
    ["class P\nrule\nend\n", :racc],
    ["class P\nrule\n", :racc],
    ["class P\nrule\ns: A;\n", :racc],
    ["token X\n", :racc],
    ["class P\nexpect nope\nrule\ns: X\nend\n", :racc],
    ["class P\nstart\n", :racc],
    ["class P\nstart 1\nrule\ns: X\nend\n", :racc],
    ["class P\nrule\ns: )\nend\n", :racc],
    ["class P\nrule\ns: ITEM*\nend\n", :racc],
    ["class P\nrule\ns: (A { x })\nend\n", :extended],
    ["class P\nrule\ns: (A\nend\n", :extended],
    ["class P\nrule\ns: (separated_list(A, B) { x })\nend\n", :extended],
    ["class P\nrule\ns: (separated_list(A, B\nend\n", :extended],
    ["class P\nrule\ns: (separated_list(A, B)\nend\n", :extended],
    ["class P\nrule\ns A\nend\n", :racc],
    ["class P\nrule\ns: ITEM:name\nend\n", :racc],
    ["class P\nrule\ns: A\nend: B\nend\n", :racc],
    ["class P\nend\n", :racc],
    ["class P\nconvert\nX abc\nend\nrule\ns: X\nend\n", :racc],
    ["class P\nconvert\nX 'one' 'two'\nend\nrule\ns: X\nend\n", :racc]
  ].freeze

  def test_public_parser_uses_generated_implementation
    parser = Ibex::Frontend::Parser.new("class P\nrule\ns: X\nend\n")

    assert_instance_of Ibex::Frontend::GeneratedParser, parser.implementation
  end

  def test_normal_load_does_not_load_bootstrap_parser
    script = <<~'RUBY'
      require "ibex"
      abort "bootstrap loaded" if defined?(Ibex::Frontend::BootstrapParser)
      parser = Ibex::Frontend::Parser.new("class P\nrule\ns: X\nend\n")
      abort "generated parser not selected" unless parser.implementation.is_a?(Ibex::Frontend::GeneratedParser)
    RUBY
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", script)

    assert status.success?, stderr
  end

  def test_frontend_can_be_required_standalone
    script = <<~'RUBY'
      require "ibex/frontend"
      ast = Ibex::Frontend::Parser.new("class P\nrule\ns: X\nend\n").parse
      abort "parse failed" unless ast.class_name == "P"
    RUBY
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", script)

    assert status.success?, stderr
  end

  def test_regenerator_does_not_load_or_depend_on_generated_parser
    Dir.mktmpdir("ibex-bootstrap") do |directory|
      FileUtils.cp_r(File.join(ROOT, "lib"), directory)
      FileUtils.rm(File.join(directory, "lib/ibex/frontend/generated_parser.rb"))
      script = <<~RUBY
        require "ibex/frontend/regenerator"
        abort "generated parser loaded" if defined?(Ibex::Frontend::GeneratedParser)
        STDOUT.binmode
        STDOUT.write(Ibex::Frontend::Regenerator.generate)
      RUBY
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", script, chdir: directory)

      assert status.success?, stderr
      assert_equal File.binread(GENERATED), stdout
    end
  end

  def test_adapter_preserves_original_token_and_location
    tokens = Ibex::Frontend::Lexer.new("class P\nrule\ns: X\nend\n", file: "identity.y").tokenize
    external, semantic_value = Ibex::Frontend::TokenAdapter.new(tokens).next_token

    assert_equal :CLASS, external
    assert_same tokens.first, semantic_value
    assert_same tokens.first.location, semantic_value.location
  end

  def test_generated_parser_matches_bootstrap_for_comprehensive_grammar
    source = File.read(FIXTURE)

    assert_equal bootstrap(source, file: "comprehensive.y").to_h,
                 generated(source, file: "comprehensive.y").to_h
  end

  def test_generated_parser_matches_bootstrap_for_extended_and_edge_grammars
    EXTENDED_FIXTURES.each do |path|
      source = File.read(path)
      file = File.basename(path)
      assert_equal bootstrap(source, file: file, mode: :extended).to_h,
                   generated(source, file: file, mode: :extended).to_h
    end
  end

  def test_generated_parser_matches_bootstrap_for_grammar_pragmas
    grammars = [
      "class P\npragma extended\nrule\ns: (A | B)+\nend\n",
      "class P\npragma future\nrule\ns: A\nend\n",
      "class P\npragma extended\npragma extended\nrule\ns: A\nend\n",
      "class P\ntoken A\npragma extended\nrule\ns: A\nend\n"
    ]

    assert_equal bootstrap(grammars[0]).to_h, generated(grammars[0]).to_h
    grammars.drop(1).each do |source|
      bootstrap_error = assert_raises(Ibex::Error) { bootstrap(source) }
      generated_error = assert_raises(Ibex::Error) { generated(source) }
      assert_equal bootstrap_error.message, generated_error.message
    end
  end

  def test_contextual_keywords_match_bootstrap
    grammars = [
      "class class::start < rule::convert\nrule\nleft: X\nend\n",
      "class P\nprechigh\nleft token start rule convert end\npreclow\nrule\ns: X\nend\n",
      "class P\nconvert\ntoken 'x'\nstart 'y'\nrule 'z'\nend\nrule\nconvert: X\nend\n",
      "class P\nrule\nstart: X\nrule: Y\nconvert: Z\nend\n"
    ]
    %w[token start rule convert end].each do |target|
      grammars << "class P\nstart #{target}\nrule\ns: X\nend\n"
    end

    grammars.each { |source| assert_equal bootstrap(source).to_h, generated(source).to_h }
  end

  def test_semicolon_resets_indentation_sensitive_rule_boundary
    source = "class P\nrule\nbase: A ;\n    deeper: B\nend\n"

    assert_equal bootstrap(source).to_h, generated(source).to_h
    assert_equal %w[base deeper], generated(source).rules.map(&:lhs)
  end

  def test_delimited_multiline_named_references_do_not_become_rule_boundaries
    grammars = [
      "class P\nrule\n  s: (\nx:name\n  )\nend\n",
      "class P\nrule\n  s: separated_list(\nx:name, ';')\nend\n"
    ]

    grammars.each do |source|
      assert_equal bootstrap(source, mode: :extended).to_h, generated(source, mode: :extended).to_h
    end
  end

  def test_end_remains_a_symbol_inside_separated_lists
    grammars = [
      "class P\nrule\ns: separated_list(end, ',')\nend\n",
      "class P\nrule\ns: separated_list(A, end)\nend\n"
    ]

    grammars.each do |source|
      assert_equal bootstrap(source, mode: :extended).to_h, generated(source, mode: :extended).to_h
    end
  end

  def test_invalid_mode_is_rejected_before_malformed_source_is_lexed
    bootstrap_error = assert_raises(ArgumentError) { bootstrap("{", mode: :invalid) }
    generated_error = assert_raises(ArgumentError) { generated("{", mode: :invalid) }

    assert_equal bootstrap_error.message, generated_error.message
  end

  def test_generated_parser_matches_bootstrap_errors
    MALFORMED_GRAMMARS.each do |source, mode|
      bootstrap_error = assert_raises(Ibex::Error) { bootstrap(source, mode: mode) }
      generated_error = assert_raises(Ibex::Error) { generated(source, mode: mode) }
      assert_equal bootstrap_error.message, generated_error.message
    end
  end

  def test_committed_parser_matches_deterministic_regeneration
    assert_equal File.binread(GENERATED), Ibex::Frontend::Regenerator.generate
  end

  def test_self_hosted_action_methods_are_private_in_runtime_and_rbs
    pattern = /\A_ibex_action_\d+\z/
    runtime_private = Ibex::Frontend::GeneratedParser.private_instance_methods(false).grep(pattern).map(&:to_s).sort
    runtime_public = Ibex::Frontend::GeneratedParser.public_instance_methods(false).grep(pattern)
    signature = File.read(GENERATED_SIGNATURE)
    rbs_private = signature.scan(/^\s+private def (_ibex_action_\d+):/).flatten.sort
    rbs_public = signature.scan(/^\s+def (_ibex_action_\d+):/).flatten

    assert_equal 68, runtime_private.length
    assert_empty runtime_public
    assert_equal runtime_private, rbs_private
    assert_empty rbs_public
    assert_respond_to Ibex::Frontend::GeneratedParser, :parser_tables
    assert_equal Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
                 Ibex::Frontend::GeneratedParser::PARSER_TABLE_FORMAT_VERSION
    assert_equal Ibex::Frontend::GeneratedParser::PARSER_TABLE_FORMAT_VERSION,
                 Ibex::Frontend::GeneratedParser.parser_tables.fetch(:format_version)
  end

  private

  def bootstrap(source, file: "grammar.y", mode: :racc)
    Ibex::Frontend::BootstrapParser.new(source, file: file, mode: mode).parse
  end

  def generated(source, file: "grammar.y", mode: :racc)
    Ibex::Frontend::Parser.new(source, file: file, mode: mode).parse
  end
end
