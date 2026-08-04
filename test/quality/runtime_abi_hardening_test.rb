# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/runtime_abi"
require_relative "../support/runtime_abi_test_project"
require "open3"

class RuntimeABIHardeningTest < Minitest::Test
  include RuntimeABITestProject

  def test_runtime_paths_cannot_omit_codegen_rbs_protection
    with_runtime_abi_root do |root|
      replace_project_text(root, "docs/runtime-abi-evolution.md", "  - sig/ibex/codegen/**/*\n", "")

      error = assert_raises(RuntimeError) { verify_runtime_abi(root) }
      assert_includes error.message, "cannot omit required protections"
      assert_includes error.message, "sig/ibex/codegen/**/*"
    end
  end

  def test_policy_validator_fixture_and_workflow_changes_require_assessment
    changed = [
      "docs/runtime-abi-evolution.md",
      "tool/quality/runtime_abi/assessment.rb",
      "test/fixtures/runtime_abi/pull_request.json",
      ".github/workflows/main.yml"
    ]
    with_runtime_abi_root do |root|
      event = fixture_event_copy(root, "pull_request_missing.json")
      changed.each do |path|
        error = assert_raises(RuntimeError) { verify_runtime_event(root, event: event, changed_paths: [path]) }
        assert_includes error.message, "complete structured ABI assessment"
      end
    end
  end

  def test_duplicate_entry_cannot_preserve_a_spoofed_96_product
    with_runtime_abi_root do |root|
      replace_project_text(root, "docs/test-interactions.md",
                           "entries: [single, multi, isolated]", "entries: [single, multi, multi]")
      replace_project_text(root, "test/matrix.yml",
                           "entries: [single, multi, isolated]", "entries: [single, multi, multi]")

      error = assert_raises(RuntimeError) { verify_runtime_abi(root) }
      assert_includes error.message, "documented matrix axes are stale"
    end
  end

  def test_interaction_row_cannot_spoof_embedded_runtime_ownership
    with_runtime_abi_root do |root|
      original = "tests: [test/packaging/runtime_gem_test.rb, test/codegen/ractor_shareability_test.rb]"
      replace_project_text(root, "docs/test-interactions.md", original, "tests: [test/runtime/parser_test.rb]")

      error = assert_raises(RuntimeError) { verify_runtime_abi(root) }
      assert_includes error.message, "interaction inventory, axes, coverage, or ownership is stale"
    end
  end

  def test_scheduled_commands_cannot_be_hidden_behind_false_condition
    with_runtime_abi_root do |root|
      condition = "if: github.event_name == 'schedule'"
      replace_project_text(root, ".github/workflows/main.yml", condition, "if: false")

      error = assert_raises(RuntimeError) { verify_runtime_abi(root) }
      assert_includes error.message, "CI gate step condition is stale"
    end
  end

  def test_real_git_diff_preserves_add_delete_rename_spaces_newlines_and_special_characters
    Dir.mktmpdir("ibex-runtime-abi-git") do |root|
      base = create_git_base(root)
      expected = create_git_changes(root)
      head = git!(root, "rev-parse", "HEAD").strip
      event = pull_request_event(base, head)
      assessment = assessment_for(root)

      paths = assessment.send(:pull_request_paths, event)
      assert_equal expected.sort, paths

      event_path = File.join(root, "event.json")
      pull_request = event.fetch("pull_request").merge("body" => "")
      File.binwrite(event_path, JSON.generate(event.merge("pull_request" => pull_request)))
      failing = assessment_for(root, event_path: event_path)
      error = assert_raises(RuntimeError) { failing.verify! }
      assert_includes error.message, "complete structured ABI assessment"
    end
  end

  def test_path_validation_rejects_non_normalized_or_invalid_utf8_bytes
    assessment = assessment_for(PROJECT_ROOT)
    ["./lib/ibex/runtime/parser.rb", "lib//ibex/runtime/parser.rb", "bad\0path", "\xFF".b].each do |path|
      assert_raises(RuntimeError) { assessment.send(:validate_paths, [path]) }
    end
  end

  private

  def create_git_base(root)
    git!(root, "init", "-q")
    git!(root, "config", "user.email", "abi-test@example.invalid")
    git!(root, "config", "user.name", "ABI Test")
    write(root, "docs/runtime-abi-evolution.md", File.binread(File.join(PROJECT_ROOT, "docs/runtime-abi-evolution.md")))
    write(root, "lib/ibex/runtime/deleted file.rb", "delete\n")
    write(root, "lib/ibex/runtime/renamed old.rb", "rename\n")
    git!(root, "add", "-A")
    git!(root, "commit", "-q", "-m", "base")
    git!(root, "rev-parse", "HEAD").strip
  end

  def create_git_changes(root)
    deleted = "lib/ibex/runtime/deleted file.rb"
    old_name = "lib/ibex/runtime/renamed old.rb"
    new_name = "lib/ibex/runtime/renamed new @.rb"
    special = "lib/ibex/runtime/space name\n$[x].rb"
    FileUtils.rm(File.join(root, deleted))
    FileUtils.mv(File.join(root, old_name), File.join(root, new_name))
    write(root, special, "special\n")
    git!(root, "add", "-A")
    git!(root, "commit", "-q", "-m", "head")
    [deleted, old_name, new_name, special]
  end

  def assessment_for(root, event_path: nil)
    contracts = Ibex::Quality::RuntimeABIContractVerifier.new(root: PROJECT_ROOT).verify!
    Ibex::Quality::RuntimeABIAssessment.new(
      root: root, contract: contracts.abi_contract, test_contract: contracts.test_contract,
      event_path: event_path, event_name: "pull_request", changed_paths: nil
    )
  end

  def pull_request_event(base, head)
    { "pull_request" => { "base" => { "sha" => base }, "head" => { "sha" => head } } }
  end

  def write(root, relative, source)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, source)
  end

  def git!(root, *arguments)
    stdout, stderr, status = Open3.capture3("git", *arguments, chdir: root)
    raise "git #{arguments.join(' ')} failed: #{stderr}" unless status.success?

    stdout
  end
end
