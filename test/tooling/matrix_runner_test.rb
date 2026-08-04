# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/matrix_runner"
require "stringio"
require "tempfile"

class MatrixRunnerTest < Minitest::Test
  def test_declared_representative_matrix_passes_and_labels_every_case
    output = StringIO.new
    count = Ibex::TestSupport::MatrixRunner.new(output: output).run

    assert_equal 12, count
    assert_equal 12, output.string.lines.length
    assert_includes output.string, "algorithm=slr"
    assert_includes output.string, "entries=isolated"
  end

  def test_missing_axis_fails_at_the_declaration_boundary
    Tempfile.create(["matrix", ".yml"]) do |file|
      file.write("axes: { algorithm: [lalr] }\nrepresentative: 1\n")
      file.flush

      error = assert_raises(KeyError) do
        Ibex::TestSupport::MatrixRunner.new(path: file.path, output: StringIO.new).run
      end
      assert_includes error.message, "table"
    end
  end

  def test_every_axis_rejects_unknown_values
    Ibex::TestSupport::MatrixRunner::AXIS_VALUES.each_key do |axis|
      configuration = YAML.safe_load_file(File.expand_path("../matrix.yml", __dir__))
      configuration.fetch("axes").fetch(axis)[0] = "unknown"

      with_matrix(configuration) do |path|
        error = assert_raises(ArgumentError) do
          Ibex::TestSupport::MatrixRunner.new(path: path, output: StringIO.new).run
        end
        assert_includes error.message, "matrix axis #{axis} must be exactly"
      end
    end
  end

  def test_duplicate_entry_is_rejected_even_though_the_product_is_still_ninety_six
    configuration = YAML.safe_load_file(File.expand_path("../matrix.yml", __dir__))
    configuration.fetch("axes")["entries"] = %w[single multi multi]

    with_matrix(configuration) do |path|
      error = assert_raises(ArgumentError) do
        Ibex::TestSupport::MatrixRunner.new(path: path, output: StringIO.new).run(full: true)
      end
      assert_includes error.message, "matrix axis entries must be exactly"
    end
  end

  private

  def with_matrix(configuration)
    Tempfile.create(["matrix", ".yml"]) do |file|
      file.write(YAML.dump(configuration))
      file.flush
      yield file.path
    end
  end
end
