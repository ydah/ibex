#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "stackprof"
require_relative "stackprof_summary"

profile_path = ENV.fetch("IBEX_PROFILE_RAW")
metadata_path = ENV.fetch("IBEX_PROFILE_METADATA")
interval = Integer(ENV.fetch("IBEX_PROFILE_INTERVAL_USEC"), 10)
top = Integer(ENV.fetch("IBEX_PROFILE_TOP_FRAMES"), 10)

status = nil
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
StackProf.run(mode: :wall, interval: interval, raw: true, out: profile_path) do
  require "ibex/cli"
  status = Ibex::CLI.start(ARGV)
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
raise "profiled generation failed with status #{status.inspect}" unless status&.zero?

output_option = ARGV.find { |argument| argument.start_with?("--output-file=") }
output = output_option&.delete_prefix("--output-file=")
raise "profiled generation output is unavailable" unless output && File.file?(output)

rubyopt = ENV.fetch("RUBYOPT", nil)
summary = BenchmarkSupport::StackprofSummary.build(profile_path, top: top).merge(
  "profiler_name" => "stackprof",
  "profiler_version" => StackProf::VERSION,
  "yjit_enabled" => defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : false,
  "rubyopt_sha256" => rubyopt && Digest::SHA256.hexdigest(rubyopt),
  "profiled_region_elapsed_ms" => (elapsed * 1_000).round(6),
  "generated_bytes" => File.size(output),
  "generated_sha256" => Digest::SHA256.file(output).hexdigest
)
File.write(metadata_path, "#{JSON.generate(summary)}\n")
