# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tempfile"

class CLIPragmaTest < Minitest::Test
  def test_grammar_pragma_promotes_explicit_racc_mode_to_extended
    Tempfile.create(["extended", ".y"]) do |file|
      file.write("class P\npragma extended\nrule\nstart: TOKEN+\nend\n")
      file.flush
      output = StringIO.new
      errors = StringIO.new
      status = Ibex::CLI.start(["--mode=racc", "--emit=grammar-ir", file.path],
                               stdout: output, stderr: errors)

      assert_equal 0, status, errors.string
      productions = JSON.parse(output.string).fetch("productions")
      assert(productions.any? { |production| production.dig("origin", "kind") == "plus_expansion" })
    end
  end
end
