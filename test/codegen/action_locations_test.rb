# frozen_string_literal: true

require_relative "../test_helper"

class ActionLocationsCodegenTest < Minitest::Test
  LOCATION = { file: "action.y", line: 4, column: 10 }.freeze

  def test_rewrites_only_semantic_location_expressions
    source = <<~'RUBY'
      @memo = [@1, @12, @$]
      string = "@2 @$"
      regexp = /@3/
      symbol = :"@4"
      heredoc = <<~TEXT
        @5 @$
      TEXT
      interpolated = "#{@6}"
      # @7 @$
    RUBY

    rewritten = Ibex::Codegen::ActionLocations.new(source, maximum: 12, location: LOCATION).rewrite

    assert_includes rewritten, "@memo = [_ibex_locations[0], _ibex_locations[11], _ibex_location]"
    assert_includes rewritten, 'string = "@2 @$"'
    assert_includes rewritten, "regexp = /@3/"
    assert_includes rewritten, 'symbol = :"@4"'
    assert_includes rewritten, "  @5 @$"
    assert_includes rewritten, "interpolated = \"\#{_ibex_locations[5]}\""
    assert_includes rewritten, "# @7 @$"
  end

  def test_rejects_out_of_range_and_zero_references_at_the_action_location
    ["@0", "@3"].each do |source|
      error = assert_raises(Ibex::Error) do
        Ibex::Codegen::ActionLocations.new(source, maximum: 2, location: LOCATION).rewrite
      end
      assert_match(/\Aaction\.y:4:10: semantic location #{Regexp.escape(source)} is outside 1\.\.2\z/,
                   error.message)
    end
  end

  def test_multibyte_offsets_and_interpolated_heredocs_are_rewritten_safely
    source = <<~'RUBY'
      prefix = "日本語😀𠮷"; first = @1
      text = <<~TEXT
        literal 😀𠮷 @1 @$
        semantic=#{@2[:line]} / #{@$&.column}
      TEXT
      result = [first, @2, @$, text]
    RUBY

    rewritten = Ibex::Codegen::ActionLocations.new(source, maximum: 2, location: LOCATION).rewrite

    assert_includes rewritten, 'prefix = "日本語😀𠮷"; first = _ibex_locations[0]'
    assert_includes rewritten, "  literal 😀𠮷 @1 @$"
    assert_includes rewritten,
                    "semantic=\#{_ibex_locations[1][:line]} / \#{_ibex_location&.column}"
    assert_includes rewritten, "result = [first, _ibex_locations[1], _ibex_location, text]"
    assert_equal Encoding::UTF_8, rewritten.encoding
    assert_predicate rewritten, :valid_encoding?
  end

  def test_accepts_ripper_implementations_that_return_complete_semantic_tokens
    source = "result = [@1, @$]"
    tokens = [
      [[1, 10], :on_ivar, "@1", nil],
      [[1, 14], :on_ivar, "@$", nil]
    ]

    rewritten = Ripper.stub(:lex, tokens) do
      Ibex::Codegen::ActionLocations.new(source, maximum: 1, location: LOCATION).rewrite
    end

    assert_equal "result = [_ibex_locations[0], _ibex_location]", rewritten
  end
end
