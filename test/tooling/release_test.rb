# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/release"
require "digest"
require "fileutils"
require "stringio"
require "tmpdir"

class ReleaseQualityTest < Minitest::Test
  def test_committed_stable_api_matches_the_release_baseline
    release = Ibex::Quality::Release.new(output: StringIO.new)

    assert_equal 48, release.verify_stable_api!
  end

  def test_stable_api_gate_rejects_a_changed_declaration
    Dir.mktmpdir("ibex-stable-api-test") do |root|
      signature = "module Example\nend\n"
      relative = "sig/example.rbs"
      manifest = File.join(root, "stable-api.yml")
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.binwrite(File.join(root, relative), signature)
      File.write(manifest, manifest_for(relative, signature))
      release = Ibex::Quality::Release.new(root: root, manifest: manifest, output: StringIO.new)

      assert_equal 1, release.verify_stable_api!
      File.binwrite(File.join(root, relative), "module Changed\nend\n")
      assert_raises(Ibex::Error) { release.verify_stable_api! }
    end
  end

  private

  def manifest_for(relative, signature)
    digest = Digest::SHA256.hexdigest(signature)
    <<~YAML
      ---
      version: 1
      baseline: v0.2.0
      files:
        #{relative}: #{digest}
    YAML
  end
end
