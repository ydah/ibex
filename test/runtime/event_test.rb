# frozen_string_literal: true

require_relative "../test_helper"

class RuntimeEventTest < Minitest::Test
  def test_event_document_has_stable_shape_and_is_deeply_frozen
    event = Ibex::Runtime::Event.new(
      type: :shift,
      sequence: 4,
      data: { state: 2, "location" => { "line" => 3 }, "value" => ["x"] }
    )

    assert_equal(
      {
        "ibex_runtime_event" => "runtime-event",
        "schema_version" => 1,
        "sequence" => 4,
        "event" => "shift",
        "data" => { "state" => 2, "location" => { "line" => 3 }, "value" => ["x"] }
      },
      event.to_h
    )
    assert_deeply_frozen(event.to_h)
    assert_same event.to_h, event.to_h
  end

  def test_semantic_summaries_are_bounded_and_report_cycles
    cyclic = []
    cyclic << cyclic
    long = "あ" * 200
    collection = (0..20).to_a

    summary = Ibex::Runtime::EventSanitizer.value([cyclic, collection, long])

    assert_equal({ "cycle" => true }, summary.fetch(0).fetch(0))
    assert_equal({ "omitted" => 5 }, summary.fetch(1).last)
    assert_operator summary.fetch(2).bytesize, :<=, Ibex::Runtime::EventSanitizer::MAX_STRING_BYTES
    assert summary.fetch(2).end_with?("…")
    assert_deeply_frozen(summary)
  end

  def test_invalid_strings_are_utf8_and_application_methods_are_not_called
    string_class = Class.new(String) do
      def bytesize = raise("application bytesize called")
      def encode(*) = raise("application encode called")
      def valid_encoding? = raise("application valid_encoding called")
      def is_a?(*) = true
      def inspect = raise("application inspect called")
      def to_s = raise("application to_s called")
    end
    input = string_class.new("ok\xFF".b)

    summary = Ibex::Runtime::EventSanitizer.value(input)

    assert_equal Encoding::UTF_8, summary.encoding
    assert summary.valid_encoding?
    assert_equal "ok�", summary
  end

  # The intentionally hostile subclasses keep the security boundary visible.
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def test_collection_overrides_and_prepared_like_objects_cannot_leak_identity
    array_class = Class.new(Array) do
      def length = raise("application length called")
      def fetch(*) = raise("application fetch called")
      def each(*) = raise("application each called")
      def is_a?(*) = true
      def inspect = raise("application inspect called")
    end
    hash_class = Class.new(Hash) do
      def length = raise("application length called")
      def each_pair(*) = raise("application each_pair called")
      def is_a?(*) = true
      def inspect = raise("application inspect called")
    end
    prepared_like_class = Class.new do
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def is_a?(*) = true
      def inspect = raise("application inspect called")
      def to_s = raise("application to_s called")
    end

    raw = Object.new
    array = array_class.new([raw])
    hash = hash_class.new
    Hash.instance_method(:[]=).bind(hash).call(:array, array)
    prepared_like = prepared_like_class.new(raw)
    event = Ibex::Runtime::Event.new(
      type: :shift,
      sequence: 1,
      data: { "summary" => Ibex::Runtime::EventSanitizer.value(hash), "value" => prepared_like }
    )

    assert_equal "hash", event.data.fetch("summary").fetch("type")
    assert_equal "object", event.data.fetch("value").fetch("type")
    refute_contains_identity(event.to_h, raw)
    refute_contains_identity(event.to_h, prepared_like)
    assert_deeply_frozen(event.to_h)
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def test_hostile_identity_predicates_and_large_integers_are_bounded
    hostile_class = Class.new do
      def nil? = true
      def equal?(*) = true
      def is_a?(*) = true
      def inspect = raise("application inspect called")
      def to_s = raise("application to_s called")
    end
    hostile = hostile_class.new
    event = Ibex::Runtime::Event.new(
      type: :shift,
      sequence: 1,
      data: {
        "hostile" => hostile,
        "large" => Ibex::Runtime::EventSanitizer.value(1 << 10_000)
      }
    )

    assert_equal "object", event.data.dig("hostile", "type")
    assert_equal(
      { "type" => "integer", "bits" => 10_001, "sign" => "positive" },
      event.data.fetch("large")
    )
    refute_contains_identity(event.to_h, hostile)
    assert_deeply_frozen(event.to_h)
  end

  def test_hash_input_limit_counts_colliding_sanitized_keys
    key_class = Class.new
    input = {}
    100.times { Hash.instance_method(:[]=).bind(input).call(key_class.new, Object.new) }

    event = Ibex::Runtime::Event.new(type: :shift, sequence: 1, data: { "payload" => input })
    summary = event.data.fetch("payload")

    assert_equal 2, summary.length
    assert_equal 84, summary.fetch("omitted")
  end

  def test_location_exposes_only_documented_fields
    location = Struct.new(:file, :line, :column, :end_line, :end_column, :secret)
                     .new("input.y", 2, 3, 2, 7, Object.new)

    assert_equal(
      { "file" => "input.y", "line" => 2, "column" => 3, "end_line" => 2, "end_column" => 7 },
      Ibex::Runtime::EventSanitizer.location(location)
    )
  end

  def test_failing_location_fields_are_omitted
    location = Object.new
    location.define_singleton_method(:file) { raise "unavailable" }
    location.define_singleton_method(:line) { 8 }

    assert_equal({ "line" => 8 }, Ibex::Runtime::EventSanitizer.location(location))
  end

  def test_event_validates_type_and_sequence
    assert_raises(ArgumentError) { Ibex::Runtime::Event.new(type: :unknown, sequence: 1, data: {}) }
    assert_raises(ArgumentError) { Ibex::Runtime::Event.new(type: :start, sequence: 0, data: {}) }
  end

  private

  def assert_deeply_frozen(value)
    assert_predicate value, :frozen?
    case value
    when Array
      value.each { |child| assert_deeply_frozen(child) }
    when Hash
      value.each do |key, child|
        assert_deeply_frozen(key)
        assert_deeply_frozen(child)
      end
    end
  end

  def refute_contains_identity(value, target)
    same = BasicObject.instance_method(:equal?).bind(value).call(target)
    assert !same
    case value
    when Array
      value.each { |child| refute_contains_identity(child, target) }
    when Hash
      value.each do |key, child|
        refute_contains_identity(key, target)
        refute_contains_identity(child, target)
      end
    end
  end
end
