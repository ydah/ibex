# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/runtime_abi_test_project"
require "open3"
require "rbconfig"

class RuntimeABIEntrypointTest < Minitest::Test
  include RuntimeABITestProject

  def test_ambient_pr_environment_does_not_turn_contract_task_or_unit_tests_into_pr_gate
    with_shallow_pull_request do |root, env|
      _stdout, stderr, status = run_rake_task(root, "quality:runtime_abi", env)
      assert status.success?, stderr

      _stdout, stderr, status = Open3.capture3(
        env, RbConfig.ruby, "-Itest", "test/quality/runtime_abi_test.rb", chdir: root
      )
      assert status.success?, stderr
    end
  end

  def test_pull_request_task_fails_closed_when_base_or_head_is_missing_from_shallow_checkout
    with_shallow_pull_request do |root, env|
      _stdout, stderr, status = run_rake_task(root, "quality:runtime_abi_pr", env)
      refute status.success?
      assert_includes stderr, "base commit is unavailable"

      head = git_runtime_abi!(root, "rev-parse", "HEAD").strip
      rewrite_event_shas(env.fetch("GITHUB_EVENT_PATH"), head, "0" * 40)
      _stdout, stderr, status = run_rake_task(root, "quality:runtime_abi_pr", env)
      refute status.success?
      assert_includes stderr, "head commit is unavailable"
    end
  end

  private

  def with_shallow_pull_request
    with_runtime_abi_root do |source|
      base = ensure_runtime_abi_git(source)
      File.binwrite(File.join(source, "non-runtime.txt"), "head\n")
      git_runtime_abi!(source, "add", "non-runtime.txt")
      git_runtime_abi!(source, "commit", "-q", "-m", "head")
      head = git_runtime_abi!(source, "rev-parse", "HEAD").strip

      Dir.mktmpdir("ibex-runtime-abi-shallow") do |parent|
        root = File.join(parent, "checkout")
        clone_shallow(source, root)
        assert_equal "true", git_runtime_abi!(root, "rev-parse", "--is-shallow-repository").strip
        event = File.join(root, "event.json")
        FileUtils.cp(File.join(root, "test/fixtures/runtime_abi/pull_request_missing.json"), event)
        rewrite_event_shas(event, base, head)
        env = {
          "GITHUB_EVENT_NAME" => "pull_request", "GITHUB_EVENT_PATH" => event,
          "IBEX_ABI_CHANGED_PATHS_FILE" => "/dev/null"
        }
        yield root, env
      end
    end
  end

  def clone_shallow(source, target)
    _stdout, stderr, status = Open3.capture3(
      "git", "clone", "-q", "--depth", "1", "file://#{source}", target
    )
    raise "shallow clone failed: #{stderr}" unless status.success?
  end

  def run_rake_task(root, task, env)
    expression = "load 'Rakefile'; Rake::Task[ENV.fetch('RUNTIME_ABI_TASK')].invoke"
    Open3.capture3(
      env.merge("RUNTIME_ABI_TASK" => task), RbConfig.ruby, "-rrake", "-e", expression, chdir: root
    )
  end
end
