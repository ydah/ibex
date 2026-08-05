#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require_relative "profile/lexer_profile_report"

options = {}
OptionParser.new do |command|
  command.banner = "Usage: bundle exec ruby tool/lexer_profile.rb [--output=PATH]"
  command.on("--output=PATH", "write JSON to PATH instead of stdout") { |value| options[:output] = value }
end.parse!(ARGV)

root = File.expand_path("..", __dir__)
report = Ibex::Profile::LexerProfileReport.new(root: root).build
Ibex::Profile::LexerProfileDependencies.verify_loaded!(root: root)
output = "#{JSON.pretty_generate(report)}\n"
if options[:output]
  path = File.expand_path(options.fetch(:output), root)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, output)
else
  puts output
end
