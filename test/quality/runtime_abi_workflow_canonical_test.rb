# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/runtime_abi"
require_relative "../support/runtime_abi_test_project"

class RuntimeABIWorkflowCanonicalTest < Minitest::Test
  include RuntimeABITestProject

  CHECKOUT = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"

  def test_protected_jobs_reject_skipped_auxiliary_dependencies
    %w[stage-a-safety runtime-abi-assessment].each do |job|
      with_runtime_abi_root do |root|
        auxiliary = yaml_lines(
          "  skipped-abi-prep:", "    if: false", "    runs-on: ubuntu-latest", "    steps:",
          "      - run: echo skipped", ""
        )
        replace_project_text(root, ".github/workflows/main.yml", "jobs:\n", "jobs:\n#{auxiliary}")
        replace_project_text(
          root, ".github/workflows/main.yml", "  #{job}:\n", "  #{job}:\n    needs: skipped-abi-prep\n"
        )

        assert_stale(root, job)
      end
    end
  end

  def test_runtime_abi_job_rejects_github_env_writer_and_strategy
    with_runtime_abi_root do |root|
      before = yaml_fragment("    steps:", "      - uses: #{CHECKOUT}")
      after = yaml_fragment(
        "    steps:", "      - name: Poison gate environment",
        "        run: echo 'RUBYOPT=/dev/null' >> \"$GITHUB_ENV\"", "      - uses: #{CHECKOUT}"
      )
      protected_job_mutation(root, "runtime-abi-assessment", before, after)

      assert_stale(root, "runtime-abi-assessment")
    end

    with_runtime_abi_root do |root|
      before = "  runtime-abi-assessment:\n"
      after = "  runtime-abi-assessment:\n    strategy:\n      fail-fast: false\n"
      replace_project_text(root, ".github/workflows/main.yml", before, after)

      assert_stale(root, "runtime-abi-assessment")
    end
  end

  def test_protected_jobs_reject_arbitrary_prep_and_post_steps
    with_runtime_abi_root do |root|
      before = yaml_fragment("    steps:", "      - uses: #{CHECKOUT}")
      after = yaml_fragment(
        "    steps:", "      - name: Arbitrary prep step", "        run: true", "      - uses: #{CHECKOUT}"
      )
      protected_job_mutation(root, "stage-a-safety", before, after)

      assert_stale(root, "stage-a-safety")
    end

    with_runtime_abi_root do |root|
      before = yaml_lines("        run: bundle exec rake quality:runtime_abi_pr")
      after = yaml_lines(
        "        run: bundle exec rake quality:runtime_abi_pr", "      - name: Arbitrary post step",
        "        run: true"
      )
      protected_job_mutation(root, "runtime-abi-assessment", before, after)

      assert_stale(root, "runtime-abi-assessment")
    end
  end

  private

  def assert_stale(root, job)
    error = assert_raises(RuntimeError) { verify_runtime_abi(root) }
    assert_includes error.message, "#{job} protected CI job structure is stale"
  end

  def protected_job_mutation(root, job_name, before, after)
    path = File.join(root, ".github/workflows/main.yml")
    workflow = File.binread(path)
    offset = workflow.index("  #{job_name}:\n")
    raise "#{job_name} is missing" unless offset

    prefix = workflow.byteslice(0, offset)
    job = workflow.byteslice(offset..)
    raise "#{job_name} mutation text is missing" unless job.include?(before)

    File.binwrite(path, prefix + job.sub(before, after))
  end

  def yaml_lines(*lines)
    lines.join("\n").concat("\n")
  end

  def yaml_fragment(*lines)
    lines.join("\n")
  end
end
