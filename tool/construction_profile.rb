#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require_relative "../lib/ibex"
require_relative "profile/construction_profiler"

options = { wall_seconds: 60.0, checkouts: {}, ielr_strategy: :partition }
parser = OptionParser.new do |command|
  command.banner = "Usage: bundle exec ruby tool/construction_profile.rb [options]"
  command.on("--wall-seconds=SECONDS", Float, "per-construction diagnostic wall-time limit") do |value|
    options[:wall_seconds] = value
  end
  command.on("--checkout=ID=PATH", "verified public workload checkout (repeatable)") do |value|
    identifier, path = value.split("=", 2)
    if identifier.nil? || identifier.empty? || path.nil? || path.empty?
      raise OptionParser::InvalidArgument, "checkout must be ID=PATH"
    end
    raise OptionParser::InvalidArgument, "duplicate checkout #{identifier}" if options[:checkouts].key?(identifier)

    options[:checkouts][identifier] = path
  end
  command.on("--ielr-strategy=NAME", %w[direct partition], "IELR construction strategy") do |value|
    options[:ielr_strategy] = value.to_sym
  end
  command.on("--output=PATH", "write JSON to PATH instead of stdout") { |value| options[:output] = value }
end
parser.parse!(ARGV)
raise OptionParser::InvalidArgument, "wall-seconds must be positive" unless options.fetch(:wall_seconds).positive?

root = File.expand_path("..", __dir__)
report = Ibex::Profile::ConstructionReport.new(
  root: root, wall_seconds: options.fetch(:wall_seconds), checkouts: options.fetch(:checkouts),
  ielr_strategy: options.fetch(:ielr_strategy)
).build
output = "#{JSON.pretty_generate(report)}\n"
if options[:output]
  path = File.expand_path(options.fetch(:output), root)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, output)
else
  puts output
end
