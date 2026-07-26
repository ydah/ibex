# frozen_string_literal: true

require_relative "parser_test"

# rubocop:disable Metrics/ClassLength -- event ordering assertions stay beside the shared parser fixture.
class RuntimeObservationTest < Minitest::Test
  def test_pull_events_cover_start_shift_reduce_and_accept_with_exact_payloads
    parser = RuntimeParserTest::Calculator.new([[:INT, 1, { file: "sum.y", line: 2, column: 4 }]])
    events = observe(parser)

    assert_equal 1, parser.do_parse
    assert_equal %i[start shift reduce reduce accept], events.map(&:type)
    assert_equal (1..5).to_a, events.map(&:sequence)
    assert_equal(
      {
        "driver" => "pull",
        "initial_state" => 0,
        "table_format_version" => 3,
        "grammar_digest" => nil,
        "state_count" => nil,
        "production_count" => nil
      },
      events.first.data
    )
    assert_equal(
      {
        "state" => 3,
        "token_id" => 2,
        "token" => "INT",
        "value" => 1,
        "location" => { "file" => "sum.y", "line" => 2, "column" => 4 },
        "from_state" => 0
      },
      events.fetch(1).data
    )
    assert_equal "table", events.last.data.fetch("reason")
    events.each { |event| assert_predicate event.to_h, :frozen? }
  end

  def test_pull_and_push_have_the_same_events_except_for_driver
    pull = RuntimeParserTest::Calculator.new([[:INT, 1], ["+", nil], [:INT, 2]])
    pull_events = observe(pull)
    assert_equal 3, pull.do_parse

    push = RuntimeParserTest::Calculator.new([])
    push_events = observe(push)
    assert_equal :need_more, push.push(:INT, 1)
    assert_equal :need_more, push.push("+", nil)
    assert_equal :need_more, push.push(:INT, 2)
    assert_equal 3, push.finish

    normalize = lambda do |events|
      events.map.with_index do |event, index|
        document = event.to_h
        next document unless index.zero?

        document.merge("data" => document.fetch("data").except("driver"))
      end
    end
    assert_equal normalize.call(pull_events), normalize.call(push_events)
  end

  # rubocop:disable Metrics/AbcSize -- one parse verifies that every recovery phase keeps the original context.
  def test_error_recover_discard_and_reject_use_original_bounded_context
    value = { bad: ["original"] }
    location = { file: "bad.y", line: 4, column: 2 }
    parser = RuntimeParserTest::RecoveringStatements.new(
      [[:BAD, value, location], [:BAD, "discarded"], false]
    )
    events = observe(parser)
    parser.define_singleton_method(:on_error) do |_token_id, raw, stack|
      raw[:bad] << "mutated"
      location[:line] = 99
      stack.clear
    end

    assert_nil parser.do_parse
    assert_equal %i[start error recover discard discard reject], events.map(&:type)
    error = events.find { |event| event.type == :error }
    recover = events.find { |event| event.type == :recover }
    discards = events.select { |event| event.type == :discard }
    reject = events.find { |event| event.type == :reject }
    assert_equal error.data.fetch("value"), recover.data.fetch("value")
    assert_equal error.data.fetch("location"), recover.data.fetch("location")
    assert_equal 4, recover.data.dig("location", "line")
    assert_equal "discarded", discards.last.data.fetch("value")
    assert_equal "eof_during_recovery", reject.data.fetch("reason")
  end
  # rubocop:enable Metrics/AbcSize

  def test_no_recovery_state_emits_reject_but_default_error_exception_does_not
    recovering_events = []
    parser = RuntimeParserTest::Calculator.new([["+", nil]])
    parser.observe { |event| recovering_events << event }
    parser.define_singleton_method(:on_error) { |*| nil }

    assert_nil parser.do_parse
    assert_equal %i[start error reject], recovering_events.map(&:type)
    assert_equal "no_recovery_state", recovering_events.last.data.fetch("reason")

    raising_events = []
    raising = RuntimeParserTest::Calculator.new([["+", nil]])
    raising.observe { |event| raising_events << event }
    assert_raises(Ibex::ParseError) { raising.do_parse }
    assert_equal %i[start error], raising_events.map(&:type)
  end

  def test_semantic_accept_emits_one_reduce_and_one_accept
    parser = RuntimeParserTest::AcceptingCalculator.new([[:INT, 7], ["+", nil]])
    events = observe(parser)

    assert_equal 7, parser.do_parse
    assert_equal(1, events.count { |event| event.type == :accept })
    assert_equal "semantic", events.find { |event| event.type == :accept }.data.fetch("reason")
    accept_index = events.index { |event| event.type == :accept }
    assert_equal :reduce, events.fetch(accept_index - 1).type
  end

  def test_events_after_existing_hooks_and_snapshot_values_before_hook_mutation
    value = ["original"]
    parser = RuntimeParserTest::Calculator.new([[:INT, value]])
    timeline = []
    parser.observe { |event| timeline << [:event, event.type, event.data["value"]] }
    parser.define_singleton_method(:on_shift) do |_token_id, raw, _state|
      timeline << %i[hook shift]
      raw << "mutated"
    end

    assert_same value, parser.do_parse
    shift_index = timeline.index { |entry| entry[0..1] == %i[event shift] }
    hook_index = timeline.index(%i[hook shift])
    assert_operator hook_index, :<, shift_index
    assert_equal ["original"], timeline.fetch(shift_index).fetch(2)
  end

  def test_failed_existing_hook_does_not_emit_its_event
    parser = RuntimeParserTest::Calculator.new([[:INT, 1]])
    events = observe(parser)
    parser.define_singleton_method(:on_shift) { |*| raise "hook failed" }

    assert_raises(RuntimeError) { parser.do_parse }
    assert_equal [:start], events.map(&:type)
  end

  def test_observer_mutation_uses_registration_order_and_a_dispatch_snapshot
    parser = RuntimeParserTest::Calculator.new([[:INT, 1]])
    calls = []
    added = false
    second = nil
    parser.observe do |event|
      calls << [:first, event.type]
      next if added

      added = true
      parser.observe { |later| calls << [:third, later.type] }
      parser.unobserve(second)
    end
    second = parser.observe { |event| calls << [:second, event.type] }

    parser.do_parse

    assert_equal [%i[first start], %i[second start]], calls.first(2)
    refute_includes calls.drop(2).map(&:first), :second
    assert_equal %i[first third], calls.last(2).map(&:first)
  end

  def test_observer_exception_propagates_stops_later_observers_and_releases_pull_driver
    parser = RuntimeParserTest::Calculator.new([[:INT, 1]])
    calls = []
    failing = parser.observe do |event|
      next unless event.type == :shift

      calls << :failing
      raise "observer failed"
    end
    parser.observe { |event| calls << :later if event.type == :shift }

    error = assert_raises(RuntimeError) { parser.do_parse }
    assert_equal "observer failed", error.message
    assert_equal [:failing], calls

    assert parser.unobserve(failing)
    parser.instance_variable_set(:@tokens, [[:INT, 2]])
    assert_equal 2, parser.do_parse
  end

  def test_discard_state_is_committed_before_observer_dispatch
    parser = RuntimeParserTest::RecoveringStatements.new([[:BAD, nil], [:BAD, "discarded"]])
    parser.observe { |_event| nil }
    parser.observe { |event| raise "stop after discard" if event.type == :discard }

    assert_raises(RuntimeError) { parser.do_parse }
    assert_same Ibex::Runtime::Parser::NO_LOOKAHEAD, parser.instance_variable_get(:@lookahead)
    assert_nil parser.instance_variable_get(:@lookahead_location)
  end

  def test_observer_changes_from_another_thread_are_rejected_while_driving
    parser = RuntimeParserTest::Calculator.new([[:INT, 1]])
    errors = Queue.new
    parser.observe do |event|
      next unless event.type == :start

      thread = Thread.new do
        parser.observe { |_nested| nil }
      rescue StandardError => e
        errors << e
      end
      thread.join
    end

    assert_equal 1, parser.do_parse
    assert_instance_of ThreadError, errors.pop
  end

  def test_mid_session_attach_starts_at_sequence_one_and_does_not_replay_start
    parser = RuntimeParserTest::Calculator.new([])
    assert_equal :need_more, parser.push(:INT, 5)

    events = observe(parser)
    assert_equal 5, parser.finish

    refute_empty events
    assert_equal 1, events.first.sequence
    refute_includes events.map(&:type), :start
  end

  def test_no_observer_uses_no_event_or_sanitizer_boundary
    parser = RuntimeParserTest::Calculator.new([[:INT, 1]])
    failure = ->(*) { raise "instrumentation should be dormant" }
    parser.define_singleton_method(:runtime_observer_snapshot, &failure)
    parser.define_singleton_method(:runtime_token_data, &failure)
    parser.define_singleton_method(:emit_runtime_event, &failure)

    Ibex::Runtime::Event.stub(:new, failure) do
      Ibex::Runtime::EventSanitizer.stub(:value, failure) do
        Ibex::Runtime::EventSanitizer.stub(:location, failure) do
          assert_equal 1, parser.do_parse
        end
      end
    end
  end

  private

  def observe(parser)
    events = []
    parser.observe { |event| events << event }
    events
  end
end
# rubocop:enable Metrics/ClassLength
