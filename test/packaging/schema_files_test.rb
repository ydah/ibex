# frozen_string_literal: true

require_relative "../test_helper"

class SchemaFilesPackagingTest < Minitest::Test
  def test_ir_schemas_are_packaged_in_the_gem
    specification = Gem::Specification.load(File.expand_path("../../ibex.gemspec", __dir__))

    assert_includes specification.files, "schema/grammar-ir-v1.schema.json"
    assert_includes specification.files, "schema/automaton-ir-v1.schema.json"
  end
end
