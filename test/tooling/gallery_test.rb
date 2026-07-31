# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/gallery"
require "stringio"
require "tempfile"

class GalleryTest < Minitest::Test
  def test_gallery_builds_executes_corpora_and_matches_metrics
    gallery = Ibex::Quality::Gallery.new(output: StringIO.new)

    assert_equal 3, gallery.build!
    assert_equal 3, gallery.conflicts!
  end

  def test_an_invalid_fixture_that_is_accepted_fails_the_gate
    parser = Class.new do
      def parse(_source, file:)
        file
      end
    end
    gallery = Ibex::Quality::Gallery.new(output: StringIO.new)
    expected = {
      "error_id" => "E0001", "token" => "TOKEN", "line" => 1, "column" => 1,
      "expected_tokens" => []
    }

    Tempfile.create("accepted-invalid") do |file|
      error = assert_raises(Ibex::Error) do
        gallery.send(:assert_rejected, parser, file.path, expected)
      end
      assert_includes error.message, "was expected to be rejected"
    end
  end
end
