# frozen_string_literal: true

require_relative "test_helper"
require "json_schemer"
require "stringio"
require "tempfile"

class CLIMigrationTest < Minitest::Test
  SCHEMA = JSON.parse(File.read(File.expand_path("../schema/migration-check-v1.schema.json", __dir__)))

  def test_migrate_check_emits_versioned_json_and_status
    Tempfile.create(["migration", ".y"]) do |grammar|
      grammar.write("class Legacy < Racc::Parser\nrule\nstart: TOKEN\nend\n")
      grammar.flush
      output = StringIO.new
      status = Ibex::CLI.start(
        ["migrate-check", "--format=json", grammar.path],
        stdout: output,
        stderr: StringIO.new
      )
      document = JSON.parse(output.string)

      assert_equal 1, status
      assert_equal false, document.fetch("compatible")
      assert_equal "racc.runtime_superclass", document.fetch("findings").first.fetch("code")
      assert_empty JSONSchemer.schema(SCHEMA).validate(document).to_a
    end
  end

  def test_migrate_check_accepts_a_compatible_grammar
    Tempfile.create(["migration", ".y"]) do |grammar|
      grammar.write("class Compatible\nrule\nstart: TOKEN\nend\n")
      grammar.flush
      output = StringIO.new

      assert_equal 0, Ibex::CLI.start(["migrate-check", grammar.path], stdout: output, stderr: StringIO.new)
      assert_includes output.string, "compatible with the checked racc migration surface"
    end
  end

  def test_migrate_harness_writes_atomically_after_a_successful_check
    Tempfile.create(["migration", ".y"]) do |grammar|
      Tempfile.create(["migration-harness", ".rb"]) do |output|
        grammar.write("class Compatible\nrule\nstart: TOKEN\nend\n")
        grammar.flush
        status = Ibex::CLI.start(
          ["migrate-harness", "-o", output.path, grammar.path],
          stdout: StringIO.new,
          stderr: StringIO.new
        )

        assert_equal 0, status
        source = File.read(output.path)
        assert_includes source, 'PARSER_CLASS = "Compatible"'
        assert_includes source, "executes both generated parsers"
      end
    end
  end

  def test_migrate_harness_does_not_overwrite_its_grammar
    Tempfile.create(["migration", ".y"]) do |grammar|
      source = "class Compatible\nrule\nstart: TOKEN\nend\n"
      grammar.write(source)
      grammar.flush
      errors = StringIO.new
      status = Ibex::CLI.start(
        ["migrate-harness", "-o", grammar.path, grammar.path],
        stdout: StringIO.new,
        stderr: errors
      )

      assert_equal 1, status
      assert_includes errors.string, "grammar and harness output paths must be distinct"
      assert_equal source, File.read(grammar.path)
    end
  end
end
