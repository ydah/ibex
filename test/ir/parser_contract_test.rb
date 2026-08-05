# frozen_string_literal: true

require_relative "../test_helper"

class IRParserContractTest < Minitest::Test
  def test_unspecified_contract_has_no_configuration_values_or_locations
    contract = Ibex::IR::ParserContract.new

    assert_equal({}, contract.configuration_values)
    assert_equal({}, contract.configuration_locations)
    contract.to_h.each_value do |entry|
      assert_equal({ value: nil, explicit: false, loc: nil }, entry)
    end
  end

  def test_explicit_contract_maps_to_typed_configuration_keys
    location = Ibex::Location.new(file: "contract.y", line: 4, column: 2)
    contract = Ibex::IR::ParserContract.new(
      algorithm: Ibex::IR::ParserContract::Entry.new(
        :algorithm, value: :ielr, location: location, explicit: true
      ),
      entries: Ibex::IR::ParserContract::Entry.new(
        :entries, value: :isolated, location: location, explicit: true
      )
    )

    assert_equal({ "parser.algorithm" => :ielr, "parser.entries" => :isolated }, contract.configuration_values)
    assert_equal(
      { "parser.algorithm" => location, "parser.entries" => location },
      contract.configuration_locations
    )
  end

  def test_unspecified_entry_rejects_a_value_even_when_it_is_the_builtin
    error = assert_raises(ArgumentError) do
      Ibex::IR::ParserContract::Entry.new(:algorithm, value: :lalr)
    end

    assert_equal "unspecified algorithm cannot carry a value", error.message
  end

  def test_explicit_entry_requires_a_source_location
    error = assert_raises(ArgumentError) do
      Ibex::IR::ParserContract::Entry.new(:entries, value: :shared, explicit: true)
    end

    assert_equal "explicit entries requires a source location with a file", error.message
  end
end
