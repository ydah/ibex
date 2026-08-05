#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require_relative "quality/conflict_explanation_study"

options = { write: false }
OptionParser.new do |parser|
  parser.banner = "Usage: ruby tool/conflict_explanation_study.rb [--write]"
  parser.on("--write", "replace the committed H004 machine capture") { options[:write] = true }
end.parse!

study = Ibex::Quality::ConflictExplanationStudy.new
capture = study.render
path = File.expand_path("../test/fixtures/conflict_explanations/study-v1.json", __dir__)
if options.fetch(:write)
  File.binwrite(path, capture)
  document = JSON.parse(capture)
  blind_path = File.expand_path("../docs/conflict-explanation-reviews/v1/blind-study-v1.json", __dir__)
  File.binwrite(blind_path, study.render_blind(document))
else
  $stdout.write(capture)
end
