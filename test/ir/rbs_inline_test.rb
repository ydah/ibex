# frozen_string_literal: true

require_relative "../test_helper"

class RBSInlineIRTest < Minitest::Test
  SIGNATURE = File.expand_path("../../sig/ibex/ir/grammar_ir.rbs", __dir__)

  def test_module_function_does_not_leak_into_nested_ir_classes
    signature = File.read(SIGNATURE)

    refute_includes signature, "def self?.initialize"
    refute_includes signature, "def self?.terminal?"
    assert_includes signature, "def initialize:"
    assert_includes signature, "def terminal?:"
  end
end
