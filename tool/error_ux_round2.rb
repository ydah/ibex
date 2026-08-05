# frozen_string_literal: true

require_relative "error_ux_round2/capture"

module Ibex
  module ErrorUXRound2
    module_function

    def verify?
      expected = File.binread(EVIDENCE)
      actual = Capture.new.render
      return true if expected == actual

      warn "#{EVIDENCE} is stale; regenerate it only after reviewing H003 diagnostic and repair changes"
      false
    end

    def write
      File.binwrite(EVIDENCE, Capture.new.render)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV == ["--write"]
    Ibex::ErrorUXRound2.write
    puts "wrote #{Ibex::ErrorUXRound2::EVIDENCE}"
  elsif ARGV.empty?
    exit(Ibex::ErrorUXRound2.verify? ? 0 : 1)
  else
    abort "usage: ruby tool/error_ux_round2.rb [--write]"
  end
end
