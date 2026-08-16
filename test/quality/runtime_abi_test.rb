# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/runtime_abi"
require_relative "../support/runtime_abi_test_project"

class RuntimeABITest < Minitest::Test
  include RuntimeABITestProject

  ROOT = PROJECT_ROOT

  def test_current_contract_matches_implementation
    Ibex::Quality::RuntimeABI.new(root: ROOT).verify!
  end

  def test_rejects_a_drifted_pull_request_template_rationale_sentinel
    with_root do |root|
      sentinel = Ibex::Quality::RuntimeABIReviewedPolicy::RATIONALE_SENTINEL
      replace(root, ".github/pull_request_template.md", sentinel, "Write compatibility reasoning here.")

      error = assert_raises(RuntimeError) { verify(root) }
      assert_includes error.message, "pull request template rationale sentinel is stale"
    end
  end

  def test_rejects_stale_documented_ir_version
    with_root do |root|
      replace(root, "docs/policy/runtime-abi-evolution.md", "current_writer: 1", "current_writer: 2")

      error = assert_raises(RuntimeError) { verify(root) }
      assert_includes error.message, "Grammar IR policy is stale"
    end
  end

  def test_rejects_stale_table_or_package_versions
    current_generator_version = Ibex::VERSION
    {
      "current_writer: 6" => "current_writer: 7",
      %(generator: "#{current_generator_version}") =>
        %(generator: "#{current_generator_version}.stale")
    }.each do |before, after|
      with_root do |root|
        replace(root, "docs/policy/runtime-abi-evolution.md", before, after)

        assert_raises(RuntimeError) { verify(root) }
      end
    end
  end

  def test_rejects_95_or_97_as_the_matrix_count
    [95, 97].each do |count|
      with_root do |root|
        replace(root, "docs/records/test-interactions.md", "expected_cases: 96", "expected_cases: #{count}")

        error = assert_raises(RuntimeError) { verify(root) }
        assert_includes error.message, "expected_cases must be 96"
      end
    end
  end

  def test_rejects_a_missing_matrix_axis
    with_root do |root|
      replace(root, "docs/records/test-interactions.md", "    locations: [\"off\", \"on\"]\n", "")

      error = assert_raises(RuntimeError) { verify(root) }
      assert_includes error.message, "documented matrix axes are stale or missing"
    end
  end

  def test_rejects_an_omitted_interaction
    with_root do |root|
      path = File.join(root, "docs/records/test-interactions.md")
      source = File.binread(path)
      source.sub!(/  - id: embedded_runtime\n(?:    .*\n){3}/, "")
      File.binwrite(path, source)

      error = assert_raises(RuntimeError) { verify(root) }
      assert_includes error.message, "interaction inventory, axes, coverage, or ownership is stale"
    end
  end

  def test_runtime_change_requires_an_assessment
    with_root do |root|
      error = assert_raises(RuntimeError) do
        verify_event(root, "pull_request_missing.json", "runtime-paths.txt")
      end
      assert_includes error.message, "exactly one complete structured ABI assessment"
    end
  end

  def test_runtime_change_rejects_not_applicable
    with_root do |root|
      event = event_copy(root, "pull_request.json")
      rewrite_body(event, "state: compatible", "state: not_applicable")
      rewrite_body(event, "surfaces: [runtime_api, cst]", "surfaces: [none]")
      rewrite_body(event, "abi_choice: current_contract", "abi_choice: none")
      rewrite_body(event, "regeneration: not_required", "regeneration: not_applicable")

      error = assert_raises(RuntimeError) { verify_event_path(root, event, "runtime-paths.txt") }
      assert_includes error.message, "cannot use not_applicable or none"
    end
  end

  def test_runtime_change_rejects_an_omitted_abi_choice_or_regeneration
    %w[abi_choice regeneration].each do |field|
      with_root do |root|
        event = event_copy(root, "pull_request.json")
        document = JSON.parse(File.binread(event))
        body = document.fetch("pull_request").fetch("body")
        document.fetch("pull_request")["body"] = body.lines.reject { |line| line.start_with?("#{field}:") }.join
        File.binwrite(event, JSON.pretty_generate(document))

        error = assert_raises(RuntimeError) { verify_event_path(root, event, "runtime-paths.txt") }
        assert_includes error.message, "assessment fields must be"
      end
    end
  end

  def test_runtime_change_rejects_malformed_yaml
    with_root do |root|
      event = event_copy(root, "pull_request.json")
      rewrite_body(event, "surfaces: [runtime_api, cst]", "surfaces: [runtime_api")

      error = assert_raises(RuntimeError) { verify_event_path(root, event, "runtime-paths.txt") }
      assert_includes error.message, "invalid YAML"
    end
  end

  def test_valid_compatible_assessment_passes_with_offline_event_and_diff_fixtures
    with_root do |root|
      verify_event(root, "pull_request.json", "runtime-paths.txt")
    end
  end

  def test_non_runtime_change_needs_no_assessment
    with_root do |root|
      verify_event(root, "pull_request_missing.json", "non-runtime-paths.txt")
    end
  end

  def test_push_workflow_dispatch_and_schedule_events_skip_pull_request_assessment
    with_root do |root|
      event = File.join(root, "test/fixtures/runtime_abi/push.json")
      %w[push workflow_dispatch schedule].each do |event_name|
        Ibex::Quality::RuntimeABI.new(
          root: root, event_path: event, event_name: event_name,
          changed_paths: runtime_paths(root, "runtime-paths.txt")
        ).verify!
      end
    end
  end

  private

  def with_root(&block)
    with_runtime_abi_root(&block)
  end

  def verify(root)
    Ibex::Quality::RuntimeABI.new(root: root).verify!
  end

  def verify_event(root, event_name, paths_name)
    event = event_copy(root, event_name)
    verify_event_path(root, event, paths_name)
  end

  def verify_event_path(root, event, paths_name)
    Ibex::Quality::RuntimeABI.new(
      root: root, event_path: event, event_name: "pull_request", changed_paths: runtime_paths(root, paths_name)
    ).verify!
  end

  def runtime_paths(root, name)
    File.readlines(File.join(root, "test/fixtures/runtime_abi", name), chomp: true)
  end

  def event_copy(root, name)
    fixture_event_copy(root, name)
  end

  def rewrite_body(path, before, after)
    document = JSON.parse(File.binread(path))
    body = document.fetch("pull_request").fetch("body")
    document.fetch("pull_request")["body"] = body.sub(before, after)
    File.binwrite(path, JSON.pretty_generate(document))
  end

  def replace(root, relative, before, after)
    path = File.join(root, relative)
    source = File.binread(path)
    raise "fixture text not found: #{before}" unless source.include?(before)

    File.binwrite(path, source.sub(before, after))
  end
end
