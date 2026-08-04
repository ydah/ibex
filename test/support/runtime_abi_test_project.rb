# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

module RuntimeABITestProject
  PROJECT_ROOT = File.expand_path("../..", __dir__)
  COPY_PATHS = %w[.github docs lib schema sig test tool Rakefile ibex.gemspec ibex-runtime.gemspec].freeze

  def with_runtime_abi_root
    Dir.mktmpdir("ibex-runtime-abi") do |root|
      COPY_PATHS.each { |path| FileUtils.cp_r(File.join(PROJECT_ROOT, path), File.join(root, path)) }
      yield root
    end
  end

  def verify_runtime_abi(root)
    Ibex::Quality::RuntimeABI.new(root: root).verify!
  end

  def verify_runtime_event(root, event:, changed_paths:)
    Ibex::Quality::RuntimeABI.new(
      root: root, event_path: event, event_name: "pull_request", changed_paths: changed_paths
    ).verify!
  end

  def fixture_event_copy(root, name = "pull_request.json")
    source = File.join(root, "test/fixtures/runtime_abi", name)
    target = File.join(root, "event.json")
    FileUtils.cp(source, target)
    target
  end

  def rewrite_event_body(path, before, after)
    document = JSON.parse(File.binread(path))
    body = document.fetch("pull_request").fetch("body")
    raise "event body text not found: #{before}" unless body.include?(before)

    document.fetch("pull_request")["body"] = body.sub(before, after)
    File.binwrite(path, JSON.pretty_generate(document))
  end

  def replace_project_text(root, relative, before, after)
    path = File.join(root, relative)
    source = File.binread(path)
    raise "fixture text not found: #{before}" unless source.include?(before)

    File.binwrite(path, source.sub(before, after))
  end
end
