# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/runtime_abi"
require_relative "../support/runtime_abi_test_project"
require "open3"
require "rbconfig"

class RuntimeABITrustedBaseTest < Minitest::Test
  include RuntimeABITestProject

  SHRUNK_PATHS = %w[
    .github/workflows/main.yml
    tool/quality/runtime_abi.rb
    tool/quality/runtime_abi/**/*
    lib/ibex/runtime.rb
    lib/ibex/runtime/**/*
  ].freeze

  def test_trusted_base_union_survives_head_policy_shrink_in_a_real_subprocess
    targets = [
      ".github/workflows/main.yml",
      "tool/quality/runtime_abi/reviewed_policy.rb",
      "tool/quality/runtime_abi/assessment.rb",
      "lib/ibex/runtime/parser.rb"
    ]
    targets.each do |target|
      with_runtime_abi_root do |root|
        base = ensure_runtime_abi_git(root)
        shrink_head_policy(root)
        append_project_comment(root, target) unless target.end_with?("reviewed_policy.rb")
        head = commit_all(root, "shrink head policy")
        event = assessment_event(root, base, head, target)

        _stdout, stderr, status = run_validator(root, event)
        refute status.success?, target
        assert_includes stderr, "evidence omits changed runtime-facing paths", target
        assert_includes stderr, target, target
      end
    end
  end

  def test_malformed_base_contract_fails_closed
    with_runtime_abi_root do |root|
      valid = File.binread(File.join(root, "docs/runtime-abi-evolution.md"))
      replace_project_text(root, "docs/runtime-abi-evolution.md", "runtime_paths:\n", "runtime_paths: [\n")
      base = ensure_runtime_abi_git(root)
      File.binwrite(File.join(root, "docs/runtime-abi-evolution.md"), valid)
      head = commit_all(root, "repair head contract")
      event = missing_assessment_event(root, base, head)

      error = assert_raises(RuntimeError) { verify_runtime_event(root, event: event, changed_paths: ["README.md"]) }
      assert_includes error.message, "contract is invalid YAML"
    end
  end

  def test_missing_base_commit_fails_closed
    with_runtime_abi_root do |root|
      head = ensure_runtime_abi_git(root)
      event = missing_assessment_event(root, "0" * 40, head)

      error = assert_raises(RuntimeError) { verify_runtime_event(root, event: event, changed_paths: ["README.md"]) }
      assert_includes error.message, "base commit is unavailable"
    end
  end

  def test_missing_base_contract_uses_bootstrap_paths_only_for_explicit_introduction
    with_runtime_abi_root do |root|
      contract_path = File.join(root, "docs/runtime-abi-evolution.md")
      contract = File.binread(contract_path)
      FileUtils.rm(contract_path)
      base = ensure_runtime_abi_git(root)
      File.binwrite(contract_path, contract)
      head = commit_all(root, "introduce runtime ABI contract")
      event = missing_assessment_event(root, base, head)

      error = assert_raises(RuntimeError) do
        verify_runtime_event(root, event: event, changed_paths: ["lib/ibex/runtime/parser.rb"])
      end
      assert_includes error.message, "complete structured ABI assessment"

      git_runtime_abi!(root, "rm", "-q", "docs/runtime-abi-evolution.md")
      missing_head = commit_all(root, "remove runtime ABI contract")
      trusted = trusted_base(root)
      error = assert_raises(RuntimeError) { trusted.union(pull_request_event(base, missing_head)) }
      assert_includes error.message, "trusted base runtime ABI contract is missing"
    end
  end

  private

  def shrink_head_policy(root)
    SHRUNK_PATHS.each do |pattern|
      replace_project_text(root, "docs/runtime-abi-evolution.md", "  - #{pattern}\n", "")
    end
    replace_project_text(
      root, "tool/quality/runtime_abi/reviewed_policy.rb",
      ".github/pull_request_template.md .github/workflows/main.yml Rakefile",
      ".github/pull_request_template.md Rakefile"
    )
    replace_project_text(
      root, "tool/quality/runtime_abi/reviewed_policy.rb",
      "tool/quality/runtime_abi.rb tool/quality/runtime_abi/**/*", ""
    )
    replace_project_text(
      root, "tool/quality/runtime_abi/reviewed_policy.rb",
      "lib/ibex/runtime.rb lib/ibex/runtime/**/* lib/ibex/runtime/version.rb", "lib/ibex/runtime/version.rb"
    )
  end

  def append_project_comment(root, relative)
    path = File.join(root, relative)
    File.open(path, "ab") { |file| file.write("\n# trusted-base regression\n") }
  end

  def commit_all(root, message)
    git_runtime_abi!(root, "add", "-A")
    git_runtime_abi!(root, "commit", "-q", "-m", message)
    git_runtime_abi!(root, "rev-parse", "HEAD").strip
  end

  def missing_assessment_event(root, base, head)
    source = File.join(root, "test/fixtures/runtime_abi/pull_request_missing.json")
    target = File.join(root, "event.json")
    FileUtils.cp(source, target)
    rewrite_event_shas(target, base, head)
    target
  end

  def assessment_event(root, base, head, omitted)
    source = File.join(root, "test/fixtures/runtime_abi/pull_request.json")
    target = File.join(root, "event.json")
    FileUtils.cp(source, target)
    rewrite_event_shas(target, base, head)
    evidence = ["docs/runtime-abi-evolution.md"]
    evidence << "tool/quality/runtime_abi/reviewed_policy.rb" unless omitted.end_with?("reviewed_policy.rb")
    evidence << "test/runtime/cst_serialize_test.rb"
    rewrite_event_body(
      target,
      "evidence: [lib/ibex/runtime/cst/kind.rb, test/runtime/cst_serialize_test.rb]",
      "evidence: [#{evidence.join(', ')}]"
    )
    target
  end

  def run_validator(root, event)
    env = { "GITHUB_EVENT_NAME" => "pull_request", "GITHUB_EVENT_PATH" => event }
    expression = "Ibex::Quality::RuntimeABI.new(" \
                 "event_path: ENV.fetch('GITHUB_EVENT_PATH'), " \
                 "event_name: ENV.fetch('GITHUB_EVENT_NAME')).verify!"
    Open3.capture3(env, RbConfig.ruby, "-Ilib", "-r./tool/quality/runtime_abi", "-e", expression, chdir: root)
  end

  def trusted_base(root)
    contracts = Ibex::Quality::RuntimeABIContractVerifier.new(root: PROJECT_ROOT).verify!
    Ibex::Quality::RuntimeABITrustedBase.new(root: root, head_contract: contracts.abi_contract)
  end

  def pull_request_event(base, head)
    { "pull_request" => { "base" => { "sha" => base }, "head" => { "sha" => head } } }
  end
end
