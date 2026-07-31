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
end
