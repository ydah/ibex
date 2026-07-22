# frozen_string_literal: true

require_relative "test_helper"

class RBSVisibilityTest < Minitest::Test
  SIGNATURE_ROOT = File.expand_path("../sig/ibex", __dir__)
  TARGETS = [
    [Ibex::Codegen::Dot, "codegen/dot.rbs", %i[render], %i[escape symbol_name]],
    [Ibex::Codegen::HTML, "codegen/html.rbs", %i[render],
     %i[state_sections item_html rule_sections conflict_sections escape symbol_name]],
    [Ibex::Codegen::Report, "codegen/report.rbs", %i[render],
     %i[append_state append_counterexample append_tree format_item format_action symbol_name]],
    [Ibex::IR::Serialize, "ir/serialize.rbs", %i[dump load],
     %i[validate_version load_grammar load_automaton load_state symbol_keyed normalize_action load_production
        symbolize]],
    [Ibex::LALR::DefaultReductions, "lalr/default_reductions.rbs", %i[apply optimize], %i[select_default]],
    [Ibex::Tables, "tables.rbs", %i[build], %i[runtime_action]],
    [Ibex::Tables::Compact, "tables.rbs", %i[build], %i[find_offset]]
  ].freeze

  def test_runtime_singleton_visibility_matches_the_intended_api
    TARGETS.each do |owner, _signature, public_methods, private_methods|
      public_methods.each do |method_name|
        message = "expected #{owner}.#{method_name} to be public"
        assert owner.singleton_class.public_method_defined?(method_name), message
        assert_respond_to owner, method_name
      end
      private_methods.each do |method_name|
        message = "expected #{owner}.#{method_name} to be private"
        assert owner.singleton_class.private_method_defined?(method_name), message
        refute_respond_to owner, method_name
        assert_raises(NoMethodError) { owner.public_send(method_name) }
      end
    end
  end

  def test_generated_rbs_preserves_singleton_visibility
    private_count = 0
    TARGETS.each do |_owner, signature_path, public_methods, private_methods|
      signature = File.read(File.join(SIGNATURE_ROOT, signature_path))
      public_methods.each { |method_name| assert_match(/^\s+def self\.#{method_name}:/, signature) }
      private_methods.each do |method_name|
        assert_match(/^\s+private def self\.#{method_name}:/, signature)
        private_count += 1
      end
    end
    assert_operator private_count, :>=, 24
  end
end
