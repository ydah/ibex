# frozen_string_literal: true

require_relative "../test_helper"

class RuntimeActionContractTest < Minitest::Test
  TABLES = {
    format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
    tokens: { TOKEN: 2 },
    token_names: { 0 => "$eof", 1 => "error", 2 => "TOKEN" },
    actions: [{ 2 => [:shift, 1] }, { 0 => [:reduce, 0] }, { 0 => [:accept] }],
    gotos: [{ 3 => 2 }, {}, {}],
    productions: [{ lhs: 3, length: 1, action: :consume }]
  }.freeze

  OPTIONAL_PROC = lambda do |values, stack = nil|
    [values.fetch(0), stack]
  end
  REST_PROC = lambda do |values, *rest|
    [values.fetch(0), rest.length]
  end
  MARKED_REST_PROC = lambda do |values, *rest|
    [values.fetch(0), rest.length]
  end
  SNAPSHOT_PROC = lambda do |values, stack|
    @action_values = values
    @received_stacks ||= []
    @received_stacks << stack
    stack.fetch(0).fetch(:nested) << :proc
    stack << :proc_only
    values.fetch(0)
  end

  class BaseParser < Ibex::Runtime::Parser
    def initialize(tokens)
      super()
      @tokens = tokens
    end

    def next_token = @tokens.shift
  end

  class OptionalMethodParser < BaseParser
    attr_reader :received_stack

    def self.parser_tables = TABLES

    private

    def consume(values, stack = nil)
      @received_stack = stack
      values.fetch(0)
    end
  end

  class RestMethodParser < BaseParser
    attr_reader :action_argument_count

    def self.parser_tables = TABLES

    private

    def consume(*arguments)
      @action_argument_count = arguments.length
      arguments.fetch(0).fetch(0)
    end
  end

  class OptionalProcParser < BaseParser
    TABLES = RuntimeActionContractTest::TABLES.merge(
      productions: [{ lhs: 3, length: 1, action: RuntimeActionContractTest::OPTIONAL_PROC }]
    ).freeze

    def self.parser_tables = TABLES
  end

  class RestProcParser < BaseParser
    TABLES = RuntimeActionContractTest::TABLES.merge(
      productions: [{ lhs: 3, length: 1, action: RuntimeActionContractTest::REST_PROC }]
    ).freeze

    def self.parser_tables = TABLES
  end

  class MarkedProcParser < BaseParser
    TABLES = RuntimeActionContractTest::TABLES.merge(
      productions: [
        { lhs: 3, length: 1, action: RuntimeActionContractTest::MARKED_REST_PROC, location_action: true }
      ]
    ).freeze

    def self.parser_tables = TABLES
  end

  class SnapshotMethodParser < BaseParser
    attr_reader :action_values, :received_stacks

    def self.parser_tables = TABLES

    private

    def consume(values, stack)
      @action_values = values
      @received_stacks ||= []
      @received_stacks << stack
      stack.fetch(0).fetch(:nested) << :method
      stack << :method_only
      values.fetch(0)
    end
  end

  class SnapshotProcParser < BaseParser
    TABLES = RuntimeActionContractTest::TABLES.merge(
      productions: [{ lhs: 3, length: 1, action: RuntimeActionContractTest::SNAPSHOT_PROC }]
    ).freeze

    attr_reader :action_values, :received_stacks

    def self.parser_tables = TABLES
  end

  class GeneratedMethodParser < BaseParser
    ACTION_NAME = :_ibex_action_0 # rubocop:disable Naming/VariableNumber
    TABLES = RuntimeActionContractTest::TABLES.merge(
      productions: [{ lhs: 3, length: 1, action: ACTION_NAME, location_action: true }]
    ).freeze

    attr_reader :action_arguments

    def self.parser_tables = TABLES

    private

    define_method(ACTION_NAME) do |values, stack, locations, location_stack, location|
      @action_arguments = [values, stack, locations, location_stack, location]
      [locations, location]
    end
  end

  class VersionOneGeneratedShapeParser < BaseParser
    ACTION_NAME = :_ibex_action_0 # rubocop:disable Naming/VariableNumber
    TABLES = RuntimeActionContractTest::TABLES.merge(
      format_version: 1,
      productions: [
        { lhs: 3, length: 1, action: ACTION_NAME, location_action: true, composition_action: true }
      ]
    ).freeze

    attr_reader :action_argument_count

    def self.parser_tables = TABLES

    private

    define_method(ACTION_NAME) do |values, _stack|
      @action_argument_count = 2
      values.fetch(0)
    end
  end

  class VersionTwoGeneratedShapeParser < BaseParser
    ACTION_NAME = :_ibex_action_0 # rubocop:disable Naming/VariableNumber
    TABLES = RuntimeActionContractTest::TABLES.merge(
      format_version: 2,
      productions: [
        { lhs: 3, length: 1, action: ACTION_NAME, location_action: true, composition_action: true }
      ]
    ).freeze

    attr_reader :action_argument_count

    def self.parser_tables = TABLES

    private

    define_method(ACTION_NAME) do |values, _stack, _locations, _location_stack, _location|
      @action_argument_count = 5
      values.fetch(0)
    end
  end

  class VersionThreeComposedShapeParser < BaseParser
    ACTION_NAME = :_ibex_action_0 # rubocop:disable Naming/VariableNumber
    TABLES = RuntimeActionContractTest::TABLES.merge(
      format_version: 3,
      productions: [
        { lhs: 3, length: 1, action: ACTION_NAME, location_action: true, composition_action: true }
      ]
    ).freeze

    attr_reader :action_arguments

    def self.parser_tables = TABLES

    private

    define_method(ACTION_NAME) do |values, stack, locations, location_stack, location, lookahead|
      @action_arguments = [values, stack, locations, location_stack, location, lookahead]
      values.fetch(0)
    end
  end

  class InconsistentCompositionParser < BaseParser
    ACTION_NAME = :_ibex_action_0 # rubocop:disable Naming/VariableNumber
    TABLES = RuntimeActionContractTest::TABLES.merge(
      format_version: 3,
      productions: [{ lhs: 3, length: 1, action: ACTION_NAME, composition_action: true }]
    ).freeze

    def self.parser_tables = TABLES
    def next_token = raise("inconsistent parser read a token")
  end

  class VersionFourValuesShapeParser < BaseParser
    ACTION_NAME = :_ibex_action_0 # rubocop:disable Naming/VariableNumber
    TABLES = RuntimeActionContractTest::TABLES.merge(
      productions: [{ lhs: 3, length: 1, action: ACTION_NAME, values_action: true }]
    ).freeze

    attr_reader :action_argument_count

    def self.parser_tables = TABLES

    private

    define_method(ACTION_NAME) do |values|
      @action_argument_count = 1
      values.fetch(0)
    end
  end

  class VersionThreeValuesShapeParser < BaseParser
    ACTION_NAME = :_ibex_action_0 # rubocop:disable Naming/VariableNumber
    TABLES = RuntimeActionContractTest::TABLES.merge(
      format_version: 3,
      productions: [{ lhs: 3, length: 1, action: ACTION_NAME, values_action: true }]
    ).freeze

    attr_reader :action_argument_count

    def self.parser_tables = TABLES

    private

    define_method(ACTION_NAME) do |values, _stack|
      @action_argument_count = 2
      values.fetch(0)
    end
  end

  class LocatedValuesShapeParser < BaseParser
    ACTION_NAME = :_ibex_action_0 # rubocop:disable Naming/VariableNumber
    TABLES = RuntimeActionContractTest::TABLES.merge(
      uses_locations: true,
      productions: [
        {
          lhs: 3, length: 1, action: ACTION_NAME, values_action: true,
          location_names: { token: 0 }.freeze
        }
      ]
    ).freeze

    def self.parser_tables = TABLES

    private

    define_method(ACTION_NAME) do |values|
      [values.fetch(0), loc(1), loc(:token), result_loc]
    end
  end

  class InconsistentValuesParser < BaseParser
    TABLES = RuntimeActionContractTest::TABLES.merge(
      productions: [{ lhs: 3, length: 1, action: :consume, values_action: true }]
    ).freeze

    def self.parser_tables = TABLES
    def next_token = raise("inconsistent parser read a token")
  end

  class MethodMissingParser < BaseParser
    TABLES = RuntimeActionContractTest::TABLES.merge(
      productions: [{ lhs: 3, length: 1, action: :dynamic_action }]
    ).freeze

    attr_reader :action_argument_count

    def self.parser_tables = TABLES

    # Intentionally omit respond_to_missing? to preserve the historical
    # hand-written action shape that Method#call could not dispatch.
    # rubocop:disable Style/MissingRespondToMissing
    def method_missing(name, *arguments)
      return super unless name == :dynamic_action

      @action_argument_count = arguments.length
      arguments.fetch(0).fetch(0)
    end
    # rubocop:enable Style/MissingRespondToMissing
  end

  def test_unmarked_optional_and_rest_methods_always_receive_two_arguments
    optional = OptionalMethodParser.new([%i[TOKEN value]])
    rest = RestMethodParser.new([%i[TOKEN value]])

    assert_equal :value, optional.do_parse
    assert_equal [], optional.received_stack
    assert_equal :value, rest.do_parse
    assert_equal 2, rest.action_argument_count
  end

  def test_unmarked_optional_and_rest_procs_always_receive_two_arguments
    assert_equal [:value, []], OptionalProcParser.new([%i[TOKEN value]]).do_parse
    assert_equal [:value, 1], RestProcParser.new([%i[TOKEN value]]).do_parse
  end

  def test_a_marker_cannot_upgrade_an_application_proc_to_five_arguments
    assert_equal [:value, 1], MarkedProcParser.new([%i[TOKEN value]]).do_parse
  end

  def test_symbol_action_receives_a_fresh_shallow_snapshot_of_the_live_value_stack
    assert_ordinary_action_snapshot_contract(SnapshotMethodParser, :method)
  end

  def test_proc_action_receives_a_fresh_shallow_snapshot_of_the_live_value_stack
    assert_ordinary_action_snapshot_contract(SnapshotProcParser, :proc)
  end

  def test_explicitly_marked_generated_method_receives_the_location_contract
    token_location = { file: "proc.txt", line: 1, column: 2 }
    parser = GeneratedMethodParser.new([[:TOKEN, :value, token_location]])
    locations, span = parser.do_parse

    assert_equal [token_location], locations
    assert_same token_location, span.start
    assert_same token_location, span.finish
    values, stack, action_locations, location_stack, action_span = parser.action_arguments
    assert_equal [:value], values
    assert_equal [], stack
    assert_equal [token_location], action_locations
    assert_equal [], location_stack
    assert_same token_location, action_span.start
    assert_same token_location, action_span.finish
  end

  def test_version_one_generated_shape_ignores_the_location_marker
    parser = VersionOneGeneratedShapeParser.new([%i[TOKEN value]])

    assert_equal :value, parser.do_parse
    assert_equal 2, parser.action_argument_count
  end

  def test_version_two_honors_locations_but_ignores_the_composition_marker
    parser = VersionTwoGeneratedShapeParser.new([%i[TOKEN value]])

    assert_equal :value, parser.do_parse
    assert_equal 5, parser.action_argument_count
  end

  def test_version_three_composition_marker_receives_the_lookahead_location
    token_location = { file: "composition.txt", line: 2, column: 3 }
    parser = VersionThreeComposedShapeParser.new([[:TOKEN, :value, token_location]])

    assert_equal :value, parser.do_parse
    values, stack, locations, location_stack, span, lookahead = parser.action_arguments
    assert_equal [:value], values
    assert_equal [], stack
    assert_equal [token_location], locations
    assert_equal [], location_stack
    assert_same token_location, span.start
    assert_same token_location, span.finish
    assert_nil lookahead
  end

  def test_version_four_values_marker_receives_only_the_reduction_values
    parser = VersionFourValuesShapeParser.new([%i[TOKEN value]])

    assert_equal :value, parser.do_parse
    assert_equal 1, parser.action_argument_count
  end

  def test_version_three_ignores_the_values_marker
    parser = VersionThreeValuesShapeParser.new([%i[TOKEN value]])

    assert_equal :value, parser.do_parse
    assert_equal 2, parser.action_argument_count
  end

  def test_values_action_retains_public_location_helpers_on_the_generic_path
    token_location = { file: "values.txt", line: 2, column: 3 }
    value, positional, named, span =
      LocatedValuesShapeParser.new([[:TOKEN, :value, token_location]]).do_parse

    assert_equal :value, value
    assert_same token_location, positional
    assert_same token_location, named
    assert_same token_location, span.start
    assert_same token_location, span.finish
  end

  def test_version_three_rejects_an_inconsistent_composition_marker_before_input
    error = assert_raises(Ibex::Runtime::ParseError) do
      InconsistentCompositionParser.new([%i[TOKEN value]]).do_parse
    end

    assert_match(/version 3 production 0/, error.message)
    assert_match(/inconsistent :composition_action marker/, error.message)
  end

  def test_version_four_rejects_an_inconsistent_values_marker_before_input
    error = assert_raises(Ibex::Runtime::ParseError) do
      InconsistentValuesParser.new([%i[TOKEN value]]).do_parse
    end

    assert_match(/version 4 production 0/, error.message)
    assert_match(/inconsistent :values_action marker/, error.message)
  end

  def test_symbol_action_dispatches_through_method_missing
    parser = MethodMissingParser.new([%i[TOKEN value]])

    assert_equal :value, parser.do_parse
    assert_equal 2, parser.action_argument_count
  end

  private

  def assert_ordinary_action_snapshot_contract(parser_class, marker)
    parser = parser_class.new([])
    nested = []
    live_stack = [{ nested: nested }]
    values = [:result]
    parser.send(:install_value_stack, live_stack)
    production = parser_class.parser_tables.fetch(:productions).fetch(0)

    2.times do
      assert_equal :result, parser.send(:reduction_value, 0, production, values, [], nil)
    end

    assert_same values, parser.action_values
    assert_equal [marker, marker], nested
    assert_equal [{ nested: nested }], live_stack
    first, second = parser.received_stacks
    refute_same first, second
    refute_same live_stack, first
    assert_equal [{ nested: nested }, :"#{marker}_only"], first
    assert_equal [{ nested: nested }, :"#{marker}_only"], second
  end
end
