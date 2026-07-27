# frozen_string_literal: true

require_relative "test_helper"

class RBSVisibilityTest < Minitest::Test
  SIGNATURE_ROOT = File.expand_path("../sig/ibex", __dir__)
  EVENT_SANITIZER_PUBLIC = %i[data value location string class_name].freeze
  EVENT_SANITIZER_PRIVATE = %i[
    summarize json_data summarize_array summarize_hash json_array json_hash copy_array primitive? bounded_integer
    finite_float core_type? data_key truncate_utf8 object_identity location_field unavailable core_call
  ].freeze
  MODULE_FUNCTION_TARGETS = [
    [Ibex::Codegen::Dot, "codegen/dot.rbs", %i[render], %i[escape symbol_name]],
    [Ibex::Codegen::HTML, "codegen/html.rbs", %i[render],
     %i[state_sections item_html rule_sections conflict_sections escape symbol_name]],
    [Ibex::Codegen::Report, "codegen/report.rbs", %i[render],
     %i[append_state append_counterexample append_tree format_item format_action symbol_name]],
    [Ibex::IR::Serialize, "ir/serialize.rbs", %i[dump load],
     %i[validate_version load_grammar load_automaton load_state symbol_keyed normalize_action load_production
        symbolize]],
    [Ibex::LALR::DefaultReductions, "lalr/default_reductions.rbs", %i[apply optimize], %i[select_default]],
    [Ibex::Tables, "tables.rbs", %i[build], %i[runtime_action]]
  ].freeze
  SINGLETON_ONLY_TARGETS = [
    [Ibex::Tables::Compact, "tables/compact.rbs", %i[build], %i[find_offset]],
    [Ibex::Tables::CompactActions, "tables/compact_actions.rbs", %i[build pack unpack], []]
  ].freeze
  TARGETS = (MODULE_FUNCTION_TARGETS + SINGLETON_ONLY_TARGETS).freeze
  HELPER_INSTANCE_CALLS = [
    [Ibex::Codegen::Dot, :escape, ['a"b'], 'a\\"b'],
    [Ibex::Codegen::HTML, :escape, ["<item>"], "&lt;item&gt;"],
    [Ibex::Codegen::Report, :format_action, [{ type: :shift, state: 3 }], "shift 3"],
    [Ibex::IR::Serialize, :symbolize, [{ "type" => "value" }], { type: "value" }],
    [Ibex::LALR::DefaultReductions, :select_default, [{}, []], nil],
    [Ibex::Tables, :runtime_action, [{ type: :accept }], [:accept]]
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

  def test_module_functions_remain_private_callable_instance_methods
    MODULE_FUNCTION_TARGETS.each do |owner, _signature, public_methods, private_methods|
      including_class = Class.new { include owner }
      instance = including_class.new
      (public_methods + private_methods).each do |method_name|
        assert including_class.private_method_defined?(method_name)
        refute including_class.public_method_defined?(method_name)
        assert_instance_of Method, instance.method(method_name)
      end
    end

    HELPER_INSTANCE_CALLS.each do |owner, method_name, arguments, expected|
      instance = Class.new { include owner }.new
      actual = instance.send(method_name, *arguments)
      expected.nil? ? assert_nil(actual) : assert_equal(expected, actual)
    end

    assert_module_function_entries_are_callable
  end

  def test_generated_rbs_preserves_module_function_visibility
    private_count = 0
    MODULE_FUNCTION_TARGETS.each do |_owner, signature_path, public_methods, private_methods|
      signature = File.read(File.join(SIGNATURE_ROOT, signature_path))
      public_methods.each { |method_name| assert_match(/^\s+def self\?\.#{method_name}:/, signature) }
      private_methods.each do |method_name|
        assert_match(/^\s+private def #{method_name}:/, signature)
        assert_match(/^\s+private def self\.#{method_name}:/, signature)
        refute_match(/^\s+private def self\?\.#{method_name}:/, signature)
        private_count += 1
      end
    end
    assert_operator private_count, :>=, 24
  end

  def test_generated_rbs_preserves_singleton_only_visibility
    SINGLETON_ONLY_TARGETS.each do |_owner, signature_path, public_methods, private_methods|
      signature = File.read(File.join(SIGNATURE_ROOT, signature_path))
      public_methods.each { |method_name| assert_match(/^\s+def self\.#{method_name}:/, signature) }
      private_methods.each { |method_name| assert_match(/^\s+private def self\.#{method_name}:/, signature) }
    end
  end

  def test_runtime_event_internal_visibility_matches_the_typed_api
    sanitizer = Ibex::Runtime::EventSanitizer
    EVENT_SANITIZER_PUBLIC.each { |method_name| assert_respond_to sanitizer, method_name }
    EVENT_SANITIZER_PRIVATE.each do |method_name|
      assert sanitizer.singleton_class.private_method_defined?(method_name)
      refute_respond_to sanitizer, method_name
    end

    subscription_class = Ibex::Runtime::Observation::Subscription
    refute_respond_to subscription_class, :new
    refute_respond_to subscription_class, :allocate
    subscription = Ibex::Runtime::Parser.new.observe { |_event| nil }
    assert_predicate subscription, :frozen?
  end

  def test_generated_rbs_keeps_event_construction_and_sanitizer_helpers_private
    observation = File.read(File.join(SIGNATURE_ROOT, "runtime/observation.rbs"))
    assert_match(/^\s+private def self\.new:/, observation)
    assert_match(/^\s+private def self\.allocate:/, observation)

    sanitizer = File.read(File.join(SIGNATURE_ROOT, "runtime/event_sanitizer.rbs"))
    EVENT_SANITIZER_PUBLIC.each do |method_name|
      assert_match(/^\s+def self\.#{Regexp.escape(method_name.to_s)}:/, sanitizer)
    end
    EVENT_SANITIZER_PRIVATE.each do |method_name|
      assert_match(/^\s+private def self\.#{Regexp.escape(method_name.to_s)}:/, sanitizer)
    end
  end

  def test_cli_watch_boundary_exists_in_both_runtime_and_generated_rbs
    assert Ibex::CLI.private_method_defined?(:run_watch_feature)
    refute Ibex::CLI.private_method_defined?(:run_watch)

    signature = File.read(File.join(SIGNATURE_ROOT, "cli.rbs"))
    assert_match(/^\s+def run_watch_feature: \(String path\) -> Integer$/, signature)
    refute_match(/^\s+private def run_watch: /, signature)
  end

  private

  def assert_module_function_entries_are_callable
    automaton = visibility_automaton
    assert_includes included_instance(Ibex::Codegen::Dot).send(:render, automaton), "digraph ibex_automaton"
    assert_includes included_instance(Ibex::Codegen::HTML).send(:render, automaton), "<!doctype html>"
    assert_includes included_instance(Ibex::Codegen::Report).send(:render, automaton), "Algorithm: lalr1"

    serializer = included_instance(Ibex::IR::Serialize)
    serialized = serializer.send(:dump, automaton.grammar)
    assert_instance_of Ibex::IR::Grammar, serializer.send(:load, serialized)

    reductions = included_instance(Ibex::LALR::DefaultReductions)
    terminal_ids = automaton.grammar.terminals.map(&:id)
    assert_equal automaton.states.length, reductions.send(:apply, automaton.states, terminal_ids: terminal_ids).length
    assert_instance_of Ibex::IR::AutomatonState,
                       reductions.send(:optimize, automaton.states.first, terminal_ids: terminal_ids)

    tables = included_instance(Ibex::Tables).send(:build, automaton, format: :plain)
    assert_instance_of Ibex::Tables::TableSet, tables
  end

  def included_instance(owner)
    Class.new { include owner }.new
  end

  def visibility_automaton
    source = "class Visibility\nrule\nstart:\nend\n"
    ast = Ibex::Frontend::Parser.new(source, file: "visibility.y").parse
    Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
  end
end
