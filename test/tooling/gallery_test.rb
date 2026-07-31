# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/gallery"
require "stringio"

class GalleryTest < Minitest::Test
  def test_gallery_builds_executes_corpora_and_matches_metrics
    gallery = Ibex::Quality::Gallery.new(output: StringIO.new)

    assert_equal 3, gallery.build!
    assert_equal 3, gallery.conflicts!
  end
end
