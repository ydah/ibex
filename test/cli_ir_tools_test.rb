# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLIIRToolsTest < Minitest::Test
  def test_validate_ir_reports_the_document_kind
    with_grammar_irs do |before, _after|
      output = StringIO.new
      assert_equal 0, run_cli(["validate-ir", before], stdout: output)
      assert_equal "valid grammar IR v2\n", output.string
    end

    output = StringIO.new
    assert_equal 0, run_cli(["validate-ir", fixture_path("grammar-v1.json")], stdout: output)
    assert_equal "valid grammar IR v1\n", output.string
  end

  def test_validate_ir_normalizes_invalid_input_to_a_positioned_error
    Dir.mktmpdir do |directory|
      path = File.join(directory, "broken.json")
      File.write(path, '{"ibex_ir":"grammar","schema_version":1}')
      errors = StringIO.new

      assert_equal 1, run_cli(["validate-ir", path], stderr: errors)
      assert_match(/\(ir\):1:1:/, errors.string)
    end
  end

  def test_compare_reports_deterministic_structural_changes
    with_grammar_irs do |before, after|
      output = StringIO.new
      assert_equal 0, run_cli(["compare", before, after], stdout: output)
      result = JSON.parse(output.string)
      assert_equal "grammar", result.fetch("kind")
      assert_equal ["EXTRA"], result.dig("symbols", "added")
      assert_equal 1, result.dig("productions", "count", "delta")
    end
  end

  def test_compare_accepts_the_same_kind_across_schema_versions
    before = fixture_path("grammar-v1.json")
    after = fixture_path("grammar-v1-migrated-v2.json")
    output = StringIO.new

    assert_equal 0, run_cli(["compare", before, after], stdout: output)
    result = JSON.parse(output.string)
    assert_empty result.dig("symbols", "added")
    assert_empty result.dig("symbols", "removed")
    assert_equal 0, result.dig("productions", "count", "delta")
  end

  def test_migrate_ir_writes_v2_to_stdout_and_is_idempotent
    output = StringIO.new
    assert_equal 0, run_cli(["migrate-ir", fixture_path("grammar-v1.json"), "--to=2"], stdout: output)

    migrated = Ibex::IR::Validator.validate(output.string)
    assert_equal 2, migrated.schema_version
    assert_equal 1, migrated.migration.fetch(:from_schema_version)
    assert_includes migrated.migration.fetch(:unavailable), "source_provenance"

    second = StringIO.new
    assert_equal 0, run_cli(["migrate-ir", fixture_path("grammar-v1-migrated-v2.json"), "--to=2"],
                            stdout: second)
    assert_equal File.read(fixture_path("grammar-v1-migrated-v2.json")), second.string
  end

  def test_migrate_ir_atomically_writes_output_without_temporary_files
    Dir.mktmpdir do |directory|
      output = File.join(directory, "grammar.json")

      assert_equal 0, run_cli(["migrate-ir", fixture_path("grammar-v1.json"), "--to=2", "-o", output])
      assert_equal 2, Ibex::IR::Validator.validate(File.read(output)).schema_version
      assert_equal ["grammar.json"], Dir.children(directory)
    end
  end

  def test_migrate_ir_preserves_an_output_symlink
    Dir.mktmpdir do |directory|
      target = File.join(directory, "target.json")
      output = File.join(directory, "output.json")
      File.write(target, "old\n")
      File.symlink(target, output)

      assert_equal 0, run_cli(["migrate-ir", fixture_path("grammar-v1.json"), "--to=2", "-o", output])
      assert File.symlink?(output)
      assert_equal 2, Ibex::IR::Validator.validate(File.read(target)).schema_version
    end
  end

  def test_migrate_ir_honors_umask_for_a_new_output
    Dir.mktmpdir do |directory|
      output = File.join(directory, "grammar.json")
      previous = File.umask(0o077)
      begin
        assert_equal 0, run_cli(["migrate-ir", fixture_path("grammar-v1.json"), "--to=2", "-o", output])
      ensure
        File.umask(previous)
      end

      assert_equal 0o600, File.stat(output).mode & 0o777
    end
  end

  def test_migrate_ir_rejects_path_collisions_unknown_targets_and_downgrades
    source = fixture_path("grammar-v1.json")
    errors = StringIO.new
    assert_equal 1, run_cli(["migrate-ir", source, "--to=2", "-o", source], stderr: errors)
    assert_includes errors.string, "input and output paths must be distinct"

    errors = StringIO.new
    assert_equal 1, run_cli(["migrate-ir", source, "--to=99"], stderr: errors)
    assert_includes errors.string, "unsupported migration target schema_version 99"

    errors = StringIO.new
    assert_equal 1, run_cli(["migrate-ir", fixture_path("grammar-v2.json"), "--to=1"], stderr: errors)
    assert_includes errors.string, "downgrading schema_version 2 to 1 is not supported"

    errors = StringIO.new
    assert_equal 1, run_cli(["migrate-ir", source], stderr: errors)
    assert_includes errors.string, "migrate-ir requires --to=VERSION"
  end

  def test_migrate_ir_does_not_replace_output_when_input_is_invalid
    Dir.mktmpdir do |directory|
      input = File.join(directory, "invalid.json")
      output = File.join(directory, "output.json")
      File.write(input, "{}")
      File.write(output, "keep\n")

      assert_equal 1, run_cli(["migrate-ir", input, "--to=2", "-o", output])
      assert_equal "keep\n", File.read(output)
    end
  end

  private

  def with_grammar_irs
    Dir.mktmpdir do |directory|
      before = grammar_ir("class P\nrule\nstart: ITEM\nend\n")
      after = grammar_ir("class P\ntoken EXTRA\nrule\nstart: ITEM | EXTRA\nend\n")
      before_path = File.join(directory, "before.json")
      after_path = File.join(directory, "after.json")
      File.write(before_path, Ibex::IR::Serialize.dump(before))
      File.write(after_path, Ibex::IR::Serialize.dump(after))
      yield before_path, after_path
    end
  end

  def grammar_ir(source)
    ast = Ibex::Frontend::Parser.new(source, file: "compare.y").parse
    Ibex::Normalizer.new(ast).normalize
  end

  def run_cli(arguments, stdout: StringIO.new, stderr: StringIO.new)
    Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
  end

  def fixture_path(name)
    File.expand_path(File.join("fixtures", "ir", name), __dir__)
  end
end
