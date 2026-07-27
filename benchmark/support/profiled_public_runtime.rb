#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "stackprof"
require_relative "public_workload_driver"
require_relative "public_workload_manifest"
require_relative "stackprof_summary"

manifest_path, identifier, checkout, generated_output, scenario, warmup, iterations = ARGV
raise "profiled runtime arguments are incomplete" unless iterations
unless %w[warm_runtime_reuse warm_runtime_new_instance].include?(scenario)
  raise "unknown profiled runtime scenario #{scenario.inspect}"
end

workload = BenchmarkSupport::PublicWorkloadManifest.new(manifest_path).fetch(identifier)
driver = BenchmarkSupport::PublicWorkloadDriver.new(
  workload.fetch("driver"), checkout, generated_output, "ibex", racc_backend: "ruby"
).load!
reusable = driver.parser if scenario == "warm_runtime_reuse"
run_workload = lambda do
  workload.fetch("inputs").map do |input|
    parser = reusable || driver.parser
    driver.parse(parser, input)
  end
end
Integer(warmup, 10).times { run_workload.call }

profile_path = ENV.fetch("IBEX_PROFILE_RAW")
metadata_path = ENV.fetch("IBEX_PROFILE_METADATA")
interval = Integer(ENV.fetch("IBEX_PROFILE_INTERVAL_USEC"), 10)
top = Integer(ENV.fetch("IBEX_PROFILE_TOP_FRAMES"), 10)
result = nil
GC.start
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
StackProf.run(mode: :wall, interval: interval, raw: true, out: profile_path) do
  Integer(iterations, 10).times { result = run_workload.call }
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
result_sequence = Array.new(5) { run_workload.call }

rubyopt = ENV.fetch("RUBYOPT", nil)
summary = BenchmarkSupport::StackprofSummary.build(profile_path, top: top).merge(
  "profiler_name" => "stackprof",
  "profiler_version" => StackProf::VERSION,
  "yjit_enabled" => defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : false,
  "rubyopt_sha256" => rubyopt && Digest::SHA256.hexdigest(rubyopt),
  "profiled_region_elapsed_ms" => (elapsed * 1_000).round(6),
  "generated_bytes" => File.size(generated_output),
  "generated_sha256" => Digest::SHA256.file(generated_output).hexdigest,
  "result_sha256" => Digest::SHA256.hexdigest(JSON.generate(result)),
  "result_sequence_sha256" => Digest::SHA256.hexdigest(JSON.generate(result_sequence)),
  "result_sequence_length" => result_sequence.length
)
File.write(metadata_path, "#{JSON.generate(summary)}\n")
