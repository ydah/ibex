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

  class GeneratedMethodParser < BaseParser
    ACTION_NAME = :_ibex_action_0 # rubocop:disable Naming/VariableNumber
    TABLES = RuntimeActionContractTest::TABLES.merge(
      productions: [{ lhs: 3, length: 1, action: ACTION_NAME, location_action: true }]
    ).freeze

    def self.parser_tables = TABLES

    private

    define_method(ACTION_NAME) do |_values, _stack, locations, _location_stack, location|
      [locations, location]
    end
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

  def test_explicitly_marked_generated_method_receives_the_location_contract
    token_location = { file: "proc.txt", line: 1, column: 2 }
    locations, span = GeneratedMethodParser.new([[:TOKEN, :value, token_location]]).do_parse

    assert_equal [token_location], locations
    assert_same token_location, span.start
    assert_same token_location, span.finish
  end
end
