# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/runtime_abi"
require_relative "../support/runtime_abi_test_project"

class RuntimeABIWorkflowTest < Minitest::Test
  include RuntimeABITestProject

  def test_push_pull_request_and_schedule_triggers_are_mandatory
    %w[push pull_request schedule].each do |trigger|
      with_runtime_abi_root do |root|
        replace_project_text(root, ".github/workflows/main.yml", "  #{trigger}:\n", "  disabled_#{trigger}:\n")

        error = assert_raises(RuntimeError) { verify_runtime_abi(root) }
        assert_includes error.message, "CI has missing or stale required triggers"
        assert_includes error.message, trigger
      end
    end
  end

  def test_required_trigger_shapes_are_exact
    mutations = [
      ["    branches:\n      - main\n", "    branches:\n      - ignored\n", "push"],
      ["  pull_request:\n", "  pull_request: false\n", "pull_request"],
      ["    - cron: '27 3 * * 1'\n", "    - cron: '27 3 * * 2'\n", "schedule"]
    ]
    mutations.each do |before, after, trigger|
      with_runtime_abi_root do |root|
        replace_project_text(root, ".github/workflows/main.yml", before, after)

        error = assert_raises(RuntimeError) { verify_runtime_abi(root) }
        assert_includes error.message, "stale required triggers"
        assert_includes error.message, trigger
      end
    end
  end

  def test_protected_jobs_reject_conditions_continue_on_error_and_shell_defaults
    mutations = [
      ["  stage-a-safety:\n", "  stage-a-safety:\n    if: false\n", "fail-open controls"],
      ["  v1-contracts:\n", "  v1-contracts:\n    continue-on-error: false\n", "fail-open controls"],
      ["name: CI\n", "name: CI\n\ndefaults:\n  run:\n    shell: bash {0}\n", "default safe shell"],
      ["  stage-a-safety:\n",
       "  stage-a-safety:\n    defaults:\n      run:\n        shell: bash {0}\n", "fail-open controls"]
    ]
    mutations.each do |before, after, message|
      with_runtime_abi_root do |root|
        replace_project_text(root, ".github/workflows/main.yml", before, after)

        error = assert_raises(RuntimeError) { verify_runtime_abi(root) }
        assert_includes error.message, message
      end
    end
  end

  def test_gate_step_conditions_are_exact
    mutations = [
      ["      - name: Verify deterministic safety gates\n",
       "      - name: Verify deterministic safety gates\n        if: false\n", "unconditional"],
      ["        if: github.event_name == 'schedule'\n", "        if: false\n", "condition is stale"],
      ["        if: github.event_name == 'pull_request'\n", "        if: true\n", "condition is stale"]
    ]
    mutations.each do |before, after, message|
      with_runtime_abi_root do |root|
        replace_project_text(root, ".github/workflows/main.yml", before, after)

        error = assert_raises(RuntimeError) { verify_runtime_abi(root) }
        assert_includes error.message, message
      end
    end
  end

  def test_gate_commands_reject_fail_open_or_background_additions
    mutations = [
      ["          bundle exec rake test:matrix\n", "          set +e\n          bundle exec rake test:matrix\n",
       "normal gate commands are stale"],
      ["        run: bundle exec rake quality:runtime_abi\n",
       "        run: bundle exec rake quality:runtime_abi || true\n", "enforcement commands are stale"],
      ["          bundle exec rake fuzz:long\n", "          bundle exec rake fuzz:long &\n",
       "scheduled gate commands are stale"]
    ]
    mutations.each do |before, after, message|
      with_runtime_abi_root do |root|
        replace_project_text(root, ".github/workflows/main.yml", before, after)

        error = assert_raises(RuntimeError) { verify_runtime_abi(root) }
        assert_includes error.message, message
      end
    end
  end

  def test_gate_steps_reject_shell_and_continue_on_error_overrides
    mutations = [
      ["      - name: Verify deterministic safety gates\n",
       "      - name: Verify deterministic safety gates\n        shell: bash\n"],
      ["      - name: Enforce pull-request runtime ABI assessment\n",
       "      - name: Enforce pull-request runtime ABI assessment\n        continue-on-error: false\n"]
    ]
    mutations.each do |before, after|
      with_runtime_abi_root do |root|
        replace_project_text(root, ".github/workflows/main.yml", before, after)

        error = assert_raises(RuntimeError) { verify_runtime_abi(root) }
        assert_includes error.message, "fail-open controls"
      end
    end
  end

  def test_scheduled_gate_environment_is_exact
    with_runtime_abi_root do |root|
      replace_project_text(
        root, ".github/workflows/main.yml", "IBEX_ADVERSARIAL_FULL: '1'", "IBEX_ADVERSARIAL_FULL: '0'"
      )

      error = assert_raises(RuntimeError) { verify_runtime_abi(root) }
      assert_includes error.message, "scheduled gate environment is stale"
    end
  end
end
