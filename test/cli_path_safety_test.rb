# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLIPathSafetyTest < Minitest::Test
  def test_generation_rejects_symlink_and_hardlink_aliases_of_the_input
    Dir.mktmpdir("ibex-output-alias") do |directory|
      source = File.join(directory, "source.rb")
      grammar = File.join(directory, "grammar.y")
      original = "class P\nrule\nstart: TOKEN\nend\n"
      File.write(source, original)
      File.symlink(source, grammar)

      assert_alias_rejected(source, grammar, original)

      File.unlink(grammar)
      File.link(source, grammar)
      assert_alias_rejected(source, grammar, original)
    end
  end

  def test_resumed_pipeline_reports_invalid_ir_without_leaking_loader_errors
    Dir.mktmpdir("ibex-invalid-ir") do |directory|
      path = File.join(directory, "broken.json")
      File.write(path, '{"ibex_ir":"grammar","schema_version":1}')
      errors = StringIO.new

      status = Ibex::CLI.start(["--from=grammar-ir", path], stdout: StringIO.new, stderr: errors)

      assert_equal 1, status
      assert_match(/\(ir\):1:1:/, errors.string)
    end
  end

  private

  def assert_alias_rejected(output, grammar, original)
    errors = StringIO.new
    status = Ibex::CLI.start(["-o", output, grammar], stdout: StringIO.new, stderr: errors)
    assert_equal 1, status
    assert_match(/paths must be distinct/, errors.string)
    assert_equal original, File.read(output)
  end
end
