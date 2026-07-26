# frozen_string_literal: true

require "digest"
require "etc"
require "rbconfig"
require "time"
require_relative "table_metrics"

module BenchmarkSupport
  # Collects one versioned, deterministic benchmark structure plus observations.
  class Artifact
    STAGES = %i[parse normalize automaton table_plain table_compact codegen_plain codegen_compact].freeze

    def initialize(root, options)
      @root = root
      @options = options
      @samples = STAGES.to_h { |stage| [stage, []] }
    end

    def run
      source = File.read(path_for(:grammar))
      input = workload_input(File.read(path_for(:input)))
      result = repeat_builds(source)
      runtime = measure_runtime(result, input)
      report(source, input, result, runtime)
    end

    private

    def repeat_builds(source)
      result = nil
      digest = nil
      @options.fetch(:iterations).times do
        result = build_once(source)
        current = build_digest(result)
        raise "pipeline output changed between identical iterations" if digest && digest != current

        digest = current
      end
      result.merge(build_digest: digest)
    end

    def build_once(source)
      ast = measure(:parse) { Ibex::Frontend::Parser.new(source, file: @options.fetch(:grammar)).parse }
      grammar = measure(:normalize) { Ibex::Normalizer.new(ast).normalize }
      builder = Ibex::LALR::Builder.new(grammar, lalr_strategy: lalr_strategy)
      automaton = measure(:automaton) { builder.build }
      plain_tables = measure(:table_plain) { Ibex::Tables.build(automaton, format: :plain) }
      compact_tables = measure(:table_compact) { Ibex::Tables.build(automaton, format: :compact) }
      plain_output = measure(:codegen_plain) { generate(automaton, :plain) }
      compact_output = measure(:codegen_compact) { generate(automaton, :compact) }
      {
        grammar: grammar,
        automaton: automaton,
        metrics: builder.metrics || raise("missing builder metrics"),
        plain_tables: plain_tables,
        compact_tables: compact_tables,
        plain_output: plain_output,
        compact_output: compact_output
      }
    end

    def generate(automaton, table)
      Ibex::Codegen::Ruby.new(automaton, table: table, line_convert: false).generate
    end

    def measure(stage)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      @samples.fetch(stage) << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      result
    end

    def measure_runtime(build, input)
      variants = %i[plain compact].to_h do |table|
        namespace = Module.new
        namespace.module_eval(build.fetch(:"#{table}_output"), "benchmark-generated-#{table}.rb")
        parser_class = namespace.const_get(:BenchmarkRepresentativeParser, false)
        result = nil
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @options.fetch(:runtime_iterations).times { result = parser_class.new.parse(input) }
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        average = milliseconds(elapsed / @options.fetch(:runtime_iterations))
        [table, { result: result, average_ms: average }]
      end
      unless variants.fetch(:plain).fetch(:result) == variants.fetch(:compact).fetch(:result)
        raise "plain and compact generated parsers returned different results"
      end

      variants
    end

    def report(source, input, result, runtime)
      plain = TableMetrics.new(result.fetch(:plain_tables), :plain).result
      compact = TableMetrics.new(result.fetch(:compact_tables), :compact).result
      digests = digests_for(source, input, result, runtime, plain, compact)
      {
        artifact: "ibex_benchmark",
        schema_version: schema_version,
        recorded_at: Time.now.utc.iso8601,
        environment: environment,
        configuration: configuration,
        measurements: measurements(runtime),
        structure: structure(result, plain, compact),
        digests: digests
      }
    end

    def measurements(runtime)
      stage_ms = @samples.transform_values { |samples| milliseconds(samples.sum / samples.length) }
      generation_stages = %i[parse normalize automaton codegen_compact]
      {
        generation_ms: generation_stages.sum { |stage| stage_ms.fetch(stage) }.round(3),
        runtime_parse_ms: runtime.transform_values { |variant| variant.fetch(:average_ms) },
        peak_rss_bytes: nil,
        stage_ms: stage_ms
      }
    end

    def structure(result, plain, compact)
      metrics = result.fetch(:metrics)
      outputs = {
        plain: result.fetch(:plain_output).bytesize,
        compact: result.fetch(:compact_output).bytesize
      }
      common = {
        productions: result.fetch(:grammar).productions.length,
        final_states: metrics.final_states,
        tables: { plain: plain.fetch(:summary), compact: compact.fetch(:summary) },
        generated_output_bytes: outputs
      }
      if schema_version == 1
        return common.merge(
          canonical_intermediate_states: metrics.canonical_states || raise("missing canonical state count")
        )
      end

      common.merge(
        construction_strategy: metrics.strategy.to_s,
        construction_intermediate_states: metrics.construction_states
      )
    end

    def digests_for(source, input, result, runtime, plain, compact)
      values = {
        grammar_source_sha256: sha256(source),
        runtime_input_sha256: sha256(input),
        grammar_ir_sha256: sha256(Ibex::IR::Serialize.dump(result.fetch(:grammar))),
        automaton_ir_sha256: sha256(Ibex::IR::Serialize.dump(result.fetch(:automaton))),
        plain_tables_sha256: sha256(plain.fetch(:document)),
        compact_tables_sha256: sha256(compact.fetch(:document)),
        plain_output_sha256: sha256(result.fetch(:plain_output)),
        compact_output_sha256: sha256(result.fetch(:compact_output)),
        runtime_result_sha256: sha256(JSON.generate(runtime.fetch(:compact).fetch(:result)))
      }
      values[:artifact_sha256] = sha256(JSON.generate(values))
      values
    end

    def canonical_table_document(tables, kind)
      TableMetrics.new(tables, kind).document
    end

    def environment
      {
        ruby_engine: RUBY_ENGINE,
        ruby_version: RUBY_VERSION,
        ruby_platform: RUBY_PLATFORM,
        ibex_version: Ibex::VERSION,
        host_os: RbConfig::CONFIG.fetch("host_os"),
        host_cpu: RbConfig::CONFIG.fetch("host_cpu"),
        processors: Etc.nprocessors
      }
    end

    def configuration
      {
        grammar: @options.fetch(:grammar),
        input: @options.fetch(:input),
        seed: @options.fetch(:seed),
        build_iterations: @options.fetch(:iterations),
        runtime_iterations: @options.fetch(:runtime_iterations)
      }
    end

    def schema_version
      @options.fetch(:schema_version, 2)
    end

    def lalr_strategy
      schema_version == 1 ? :canonical_merge : :direct
    end

    def workload_input(input)
      "#{input}\nlet benchmark_seed: Number = #{@options.fetch(:seed)};\n"
    end

    def path_for(key)
      relative = @options.fetch(key)
      path = File.expand_path(relative, @root)
      raise ArgumentError, "#{key} must stay within the repository" unless path.start_with?("#{@root}/")

      path
    end

    def build_digest(result)
      sha256(
        [
          Ibex::IR::Serialize.dump(result.fetch(:grammar)),
          Ibex::IR::Serialize.dump(result.fetch(:automaton)),
          canonical_table_document(result.fetch(:plain_tables), :plain),
          canonical_table_document(result.fetch(:compact_tables), :compact),
          result.fetch(:plain_output),
          result.fetch(:compact_output)
        ].map { |value| value.is_a?(String) ? value : JSON.generate(value) }.join("\0")
      )
    end

    def milliseconds(seconds)
      (seconds * 1000).round(3)
    end

    def sha256(value)
      Digest::SHA256.hexdigest(value)
    end
  end
end
