# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/cst_incremental_property_harness"

class CSTIncrementalPropertyTest < Minitest::Test
  EDITS_PER_STAGE = Integer(ENV.fetch("IBEX_CST_PROPERTY_EDITS", "20000"), 10)
  GRAMMAR_CASES = 4
  SEED = 20_260_728

  def test_stage_a_matches_fresh_parses_for_random_grammars_inputs_and_edits
    run_property(blender: false)
  end

  def test_stage_b_matches_fresh_parses_for_random_grammars_inputs_and_edits
    assert run_property(blender: true)
  end

  private

  def run_property(blender:) # rubocop:disable Metrics/AbcSize
    random = Random.new(SEED + (blender ? 1 : 0))
    reused = false
    GRAMMAR_CASES.times do |index|
      definition = CSTIncrementalPropertyHarness.build(index: index, random: random)
      document = CSTIncrementalPropertyHarness::Document.random(definition.separator, random)
      session = definition.parser_class.incremental_session(
        Ibex::Runtime::CST::SourceText.new(document.source),
        blender: blender
      )
      (EDITS_PER_STAGE / GRAMMAR_CASES).times do
        edit = document.edit(random)
        incremental = session.edit([edit])
        batch = definition.parser_class.incremental_session(
          session.source_text,
          blender: blender
        ).result

        assert_equal document.source.b, session.source_text.text
        assert_equal document.source.b, incremental.syntax_root.to_source
        assert_equal batch.syntax_root.green, incremental.syntax_root.green
        assert_equal batch.syntax_root.green.flags, incremental.syntax_root.green.flags
        assert_equal diagnostic_snapshot(batch.diagnostics), diagnostic_snapshot(incremental.diagnostics)
        assert_equal incremental.syntax_root.green.descendant_count, session.parse_memo.left_states.length
        reused ||= session.last_blender&.reused_descendants.to_i.positive?
      end
    end
    reused
  end

  def diagnostic_snapshot(diagnostics)
    diagnostics.map do |diagnostic|
      if diagnostic.is_a?(Ibex::Runtime::ParseError)
        [
          diagnostic.class.name, diagnostic.message, diagnostic.token_id,
          diagnostic.token_name, diagnostic.token_value, diagnostic.expected_tokens,
          location_snapshot(diagnostic.location)
        ]
      else
        [
          diagnostic.fetch(:token_id), diagnostic.fetch(:value), diagnostic.fetch(:reason),
          location_snapshot(diagnostic.fetch(:location))
        ]
      end
    end
  end

  def location_snapshot(location)
    return location unless location.is_a?(Hash)

    %i[file line column end_line end_column start_byte end_byte].map { |key| [key, location[key]] }
  end
end
