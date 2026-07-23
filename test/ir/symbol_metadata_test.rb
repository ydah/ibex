# frozen_string_literal: true

require_relative "../test_helper"

class IRSymbolMetadataTest < Minitest::Test
  def test_preserves_optional_metadata_through_schema_v1
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token NUM
      display NUM "number"
      type NUM "Integer"
      type start "AST::Node"
      rule
      start: NUM
      end
    GRAMMAR
    number = grammar.symbol("NUM")
    assert_equal "number", number.display_name
    assert_equal "Integer", number.semantic_type
    assert_equal "AST::Node", grammar.symbol("start").semantic_type

    dumped = Ibex::IR::Serialize.dump(grammar)
    loaded = Ibex::IR::Serialize.load(dumped)
    assert_equal dumped, Ibex::IR::Serialize.dump(loaded)
    assert_equal "number", loaded.symbol("NUM").display_name
    assert_equal "Integer", loaded.symbol("NUM").semantic_type

    untyped = normalize("class P\nrule\nstart: TOKEN\nend\n")
    refute_includes Ibex::IR::Serialize.dump(untyped), "display_name"
    refute_includes Ibex::IR::Serialize.dump(untyped), "semantic_type"
  end

  def test_rejects_duplicate_and_unknown_metadata
    error = assert_raises(Ibex::Error) do
      normalize(<<~GRAMMAR)
        class P
        pragma extended
        display NUM "number"
        display NUM "numeric literal"
        rule
        start: NUM
        end
      GRAMMAR
    end
    assert_match(/normalize\.y:4:1: duplicate display declaration for NUM/, error.message)

    error = assert_raises(Ibex::Error) do
      normalize(<<~GRAMMAR)
        class P
        pragma extended
        type missing "String"
        rule
        start: TOKEN
        end
      GRAMMAR
    end
    assert_match(/normalize\.y:3:1: type declaration references undefined symbol missing/, error.message)
  end

  def test_load_validates_optional_metadata_at_the_symbol_location
    grammar = normalize("class P\ntoken NUM\nrule\nstart: NUM\nend\n")
    data = JSON.parse(Ibex::IR::Serialize.dump(grammar))
    symbol = data.fetch("symbols").find { |candidate| candidate.fetch("name") == "NUM" }
    symbol["loc"] = { "file" => "metadata.y", "line" => 9, "column" => 4 }
    invalid_values = [
      ["display_name", 42, "display_name must be a String or null"],
      ["display_name", "   ", "display_name must not be empty"],
      ["semantic_type", "Array[\nString]", "semantic_type must be a single line"],
      ["semantic_type", "Array[\tString]", "semantic_type must not contain control characters"]
    ]

    invalid_values.each do |field, value, message|
      candidate = JSON.parse(JSON.generate(data))
      candidate.fetch("symbols").find { |item| item.fetch("name") == "NUM" }[field] = value

      error = assert_raises(Ibex::Error) { Ibex::IR::Serialize.load(JSON.generate(candidate)) }

      assert_equal "metadata.y:9:4: #{message}", error.message
    end

    symbol["display_name"] = nil
    symbol["semantic_type"] = nil
    loaded = Ibex::IR::Serialize.load(JSON.generate(data))
    assert_nil loaded.symbol("NUM").display_name
    assert_nil loaded.symbol("NUM").semantic_type
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "normalize.y").parse
    Ibex::Normalizer.new(ast).normalize
  end
end
