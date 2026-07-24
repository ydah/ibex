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
end
