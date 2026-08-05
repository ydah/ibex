# frozen_string_literal: true

require_relative "../test_helper"
require "json_schemer"
require_relative "../../tool/profile/construction_profiler"
require_relative "../support/matrix_runner"

class ConstructionProfilerTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCHEMA = JSONSchemer.schema(JSON.parse(File.binread(File.join(ROOT, "schema/construction-profile-v1.schema.json"))))
  EVIDENCE = File.join(ROOT, "tool/profile/evidence/construction-profile-v1.json")

  def test_direct_and_ielr_structural_metrics_are_explicit
    runs = profiler.profile(normalize(<<~GRAMMAR))
      class P
      token ITEM
      rule
      start: ITEM
      end
    GRAMMAR

    direct = runs.fetch(0)
    ielr = runs.fetch(1)
    assert_equal(%w[lalr ielr], runs.map { |run| run.fetch("algorithm") })
    assert_equal "direct_lalr", direct.fetch("strategy")
    assert_equal "measured", direct.dig("structural", "propagation_edges", "status")
    assert_equal "not_applicable", direct.dig("structural", "canonical_states", "status")
    assert_equal "ielr_partition", ielr.fetch("strategy")
    assert_equal "measured", ielr.dig("structural", "canonical_states", "status")
    assert_equal "measured", ielr.dig("structural", "ielr_initial_partitions", "status")
    assert_equal "measured", ielr.dig("structural", "ielr_final_partitions", "status")
    assert_equal false, ielr.dig("observations", "elapsed_seconds", "release_gate")
  end

  def test_multi_entry_profiles_shared_and_isolated_effects_in_stable_order
    runs = profiler.profile(normalize(<<~GRAMMAR))
      class P
      pragma extended
      start first second
      token A B
      rule
      first: A
      second: B
      end
    GRAMMAR

    expected = [%w[shared lalr], %w[shared ielr], %w[isolated lalr], %w[isolated ielr]]
    actual = runs.map { |run| run.values_at("entry_mode", "algorithm") }
    assert_equal expected, actual
    assert(runs.all? { |run| run.fetch("entries") == 2 })
    assert(runs.all? { |run| run.fetch("entry_names") == %w[first second] })
  end

  def test_profile_is_opt_in_and_preserves_the_automaton
    grammar = normalize("class P\ntoken ITEM\nrule\nstart: ITEM\nend\n")
    ordinary = Ibex::LALR::Builder.new(grammar)
    profiled = Ibex::LALR::Builder.new(grammar, profile: true)

    ordinary_automaton = ordinary.build
    profiled_automaton = profiled.build
    assert_equal Ibex::IR::Serialize.dump(ordinary_automaton), Ibex::IR::Serialize.dump(profiled_automaton)
    assert_nil ordinary.metrics.lr0_states
    assert_nil ordinary.metrics.final_items
    assert_operator profiled.metrics.lr0_states, :>, 0
    assert_operator profiled.metrics.final_items, :>, 0
  end

  def test_resource_exhaustion_does_not_masquerade_as_a_negative_proof
    builder_factory = lambda do |_grammar, _algorithm, _isolated|
      Object.new.tap do |builder|
        builder.define_singleton_method(:build) { raise SystemStackError, "bounded stack" }
      end
    end
    failed = Ibex::Profile::ConstructionProfiler.new(
      wall_seconds: 1, clock: -> { 1.0 }, builder_factory: builder_factory
    ).profile(normalize("class P\nrule\nstart:\nend\n")).first

    assert_equal "resource_exhausted", failed.fetch("status")
    assert_equal({ "status" => "observed", "resource" => "stack", "limit" => nil },
                 failed.fetch("exhaustion"))
    assert_match(/SystemStackError/, failed.dig("failure", "message"))
    assert_equal "not_measured", failed.dig("structural", "lr0_states", "status")
  end

  def test_matrix_profile_source_is_the_existing_representative_fixture
    combination = {
      "algorithm" => "lalr", "table" => "plain", "cst" => "off",
      "locations" => "off", "entries" => "multi"
    }
    expected = Ibex::TestSupport::MatrixRunner.new.send(:grammar_source, combination)
    report = Ibex::Profile::ConstructionReport.new(root: ROOT, wall_seconds: 1)

    assert_equal expected, report.send(:matrix_source)
  end

  def test_committed_evidence_is_stale_until_final_recapture
    refute_empty SCHEMA.validate(committed_evidence).to_a

    document = evidence_with_current_multi_entry_decision
    assert_empty SCHEMA.validate(document).to_a
    assert_equal(%w[synthetic real], document.fetch("cohorts").map { |cohort| cohort.fetch("kind") })

    synthetic, real = document.fetch("cohorts")
    assert(synthetic.fetch("workloads").all? do |workload|
      workload.fetch("classification") == "repository_synthetic"
    end)
    public_workloads = real.fetch("workloads").select do |workload|
      workload.fetch("classification") == "public_real"
    end
    assert_equal 3, public_workloads.length
    assert(public_workloads.all? { |workload| workload.dig("availability", "status") == "not_run" })
    assert(public_workloads.all? { |workload| workload.fetch("runs").empty? })

    assert_decisions(document)
  end

  def test_explicit_invalid_public_checkout_fails_closed
    report = Ibex::Profile::ConstructionReport.new(
      root: ROOT, wall_seconds: 1, checkouts: { "namae" => File.join(ROOT, "missing-checkout") }
    )

    error = assert_raises(ArgumentError) { report.build }
    assert_match(/invalid checkout/, error.message)
  end

  def test_unknown_public_checkout_identifier_fails_closed
    report = Ibex::Profile::ConstructionReport.new(
      root: ROOT, wall_seconds: 1, checkouts: { "namame" => ROOT }
    )

    error = assert_raises(ArgumentError) { report.build }
    assert_match(/unknown public workload checkout: namame/, error.message)
  end

  def test_schema_prevents_elapsed_time_from_becoming_a_release_gate
    document = evidence_with_current_multi_entry_decision
    run = document.fetch("cohorts").first.fetch("workloads").first.fetch("runs").first
    run.dig("observations", "elapsed_seconds")["release_gate"] = true

    refute_empty SCHEMA.validate(document).to_a
  end

  def test_schema_prevents_source_class_and_availability_cross_contamination
    document = evidence_with_current_multi_entry_decision
    synthetic = document.fetch("cohorts").first.fetch("workloads").first
    synthetic["classification"] = "public_real"
    refute_empty SCHEMA.validate(document).to_a

    document = evidence_with_current_multi_entry_decision
    public_workload = document.fetch("cohorts").last.fetch("workloads").find do |workload|
      workload.fetch("classification") == "public_real"
    end
    public_workload["runs"] << document.fetch("cohorts").first.fetch("workloads").first.fetch("runs").first
    refute_empty SCHEMA.validate(document).to_a
  end

  private

  def committed_evidence
    JSON.parse(File.binread(EVIDENCE))
  end

  def evidence_with_current_multi_entry_decision
    document = committed_evidence
    index = document.fetch("decisions").index do |decision|
      decision.fetch("feature") == "direct-multi-entry"
    end
    replacement = Ibex::Profile::ConstructionDecisions.new(document.fetch("cohorts")).build.find do |decision|
      decision.fetch("feature") == "direct-multi-entry"
    end
    document.fetch("decisions")[index] = replacement
    document
  end

  def assert_decisions(document)
    decisions = document.fetch("decisions").to_h { |decision| [decision.fetch("feature"), decision] }
    assert_equal "NO-GO", decisions.fetch("direct-ielr").fetch("decision")
    assert_equal "MORE DATA", decisions.fetch("direct-multi-entry").fetch("decision")
    assert_equal(
      %w[
        representative-real-multi-entry
        material-canonical-fallback-cost
        clear-shared-benefit-over-isolation
        conflict-attribution-preservation
      ],
      decisions.fetch("direct-multi-entry").fetch("thresholds").map { |item| item.fetch("id") }
    )
    verifier_threshold = threshold(decisions.fetch("direct-ielr"), "verifier-tcb")
    assert verifier_threshold.fetch("satisfied")
    refute threshold(decisions.fetch("direct-ielr"), "scale-independent-verification").fetch("satisfied")
  end

  def threshold(decision, id)
    decision.fetch("thresholds").find { |item| item.fetch("id") == id }
  end

  def profiler
    Ibex::Profile::ConstructionProfiler.new(wall_seconds: 1, clock: -> { 1.0 })
  end

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "profile.y", mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended).normalize
  end
end
