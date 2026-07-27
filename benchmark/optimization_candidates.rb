#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "rbconfig"
require "time"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ibex"

# rubocop:disable Metrics/ModuleLength -- one executable owns the complete isolated experiment protocol.
module OptimizationCandidates
  ROOT = File.expand_path("..", __dir__)
  GRAMMAR_PATH = File.join(ROOT, "benchmark/grammars/representative.y")
  INPUT_PATH = File.join(ROOT, "benchmark/grammars/representative.input")
  DEFAULTS = { runs: 5, warmup: 100, iterations: 1_000, output: nil }.freeze

  module_function

  def run(arguments)
    return run_worker(arguments) if arguments.first == "--worker"

    options = parse_options(arguments)
    report = parent_report(options)
    output = "#{JSON.pretty_generate(report)}\n"
    File.write(options.fetch(:output), output) if options[:output]
    puts output
  end

  def parse_options(arguments)
    options = DEFAULTS.dup
    OptionParser.new do |parser|
      parser.banner = "Usage: benchmark/optimization_candidates.rb [options]"
      parser.on("--runs N", Integer, "isolated processes per variant") { |value| options[:runs] = value }
      parser.on("--warmup N", Integer, "warmup parses per process") { |value| options[:warmup] = value }
      parser.on("--iterations N", Integer, "measured parses per process") { |value| options[:iterations] = value }
      parser.on("--output PATH", "write the JSON report") { |value| options[:output] = value }
    end.parse!(arguments)
    %i[runs warmup iterations].each do |key|
      raise OptionParser::InvalidArgument, "#{key} must be positive" unless options.fetch(key).positive?
    end
    if options.fetch(:runs) < 5
      raise OptionParser::InvalidArgument, "the comparison requires at least five isolated runs"
    end

    options
  end

  def parent_report(options)
    variants = %w[table case].to_h do |variant|
      observations = Array.new(options.fetch(:runs)) { worker_observation(variant, options) }
      [variant, observations]
    end
    assert_equivalent!(variants)
    report_document(options, variants, candidate_statistics(variants))
  end

  def candidate_statistics(variants)
    baseline = median(variants.fetch("table").map { |entry| entry.fetch("runtime_ms") })
    candidate = median(variants.fetch("case").map { |entry| entry.fetch("runtime_ms") })
    baseline_bytes = variants.fetch("table").first.fetch("generated_bytes")
    candidate_bytes = variants.fetch("case").first.fetch("generated_bytes")
    runtime_improvement = percentage(baseline - candidate, baseline)
    size_change = percentage(candidate_bytes - baseline_bytes, baseline_bytes)
    {
      baseline: baseline,
      candidate: candidate,
      baseline_bytes: baseline_bytes,
      candidate_bytes: candidate_bytes,
      runtime_improvement: runtime_improvement,
      size_change: size_change,
      qualifies: runtime_improvement >= 5.0 && size_change < 5.0
    }
  end

  def report_document(options, variants, statistics)
    reference = variants.fetch("table").first
    {
      experiment: "ibex_optimization_candidates",
      schema_version: 1,
      recorded_at: Time.now.utc.iso8601,
      environment: environment,
      configuration: options.except(:output),
      observations: {
        table_runtime_ms: variants.fetch("table").map { |entry| entry.fetch("runtime_ms") },
        case_runtime_ms: variants.fetch("case").map { |entry| entry.fetch("runtime_ms") }
      },
      medians: {
        table_runtime_ms: statistics.fetch(:baseline),
        case_runtime_ms: statistics.fetch(:candidate)
      },
      structure: candidate_structure(statistics),
      digests: {
        source_sha256: reference.fetch("source_sha256"),
        automaton_sha256: reference.fetch("automaton_sha256"),
        result_sha256: reference.fetch("result_sha256")
      },
      comparison: {
        case_runtime_improvement_percent: statistics.fetch(:runtime_improvement),
        case_generated_size_change_percent: statistics.fetch(:size_change),
        case_qualifies: statistics.fetch(:qualifies)
      },
      chain_rule_audit: chain_rule_audit
    }
  end

  def candidate_structure(statistics)
    {
      table_generated_bytes: statistics.fetch(:baseline_bytes),
      case_generated_bytes: statistics.fetch(:candidate_bytes)
    }
  end

  def run_worker(arguments)
    _worker, variant, warmup, iterations = arguments
    raise ArgumentError, "unknown candidate #{variant.inspect}" unless %w[table case].include?(variant)

    source, input, automaton = build_inputs
    generated = generated_source(automaton, variant)
    namespace = Module.new
    namespace.module_eval(generated, "optimization-candidate-#{variant}.rb")
    parser_class = namespace.const_get(:BenchmarkRepresentativeParser, false)
    Integer(warmup, 10).times { parser_class.new.parse(input) }
    result = nil
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Integer(iterations, 10).times { result = parser_class.new.parse(input) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    puts JSON.generate(
      variant: variant,
      runtime_ms: ((elapsed / Integer(iterations, 10)) * 1_000).round(6),
      generated_bytes: generated.bytesize,
      source_sha256: Digest::SHA256.hexdigest(source),
      automaton_sha256: Digest::SHA256.hexdigest(Ibex::IR::Serialize.dump(automaton)),
      result_sha256: Digest::SHA256.hexdigest(Marshal.dump(result))
    )
  end

  def worker_observation(variant, options)
    command = [
      RbConfig.ruby, __FILE__, "--worker", variant,
      options.fetch(:warmup).to_s, options.fetch(:iterations).to_s
    ]
    stdout, stderr, status = Open3.capture3(*command)
    raise "candidate worker failed: #{stderr}#{stdout}" unless status.success?

    JSON.parse(stdout)
  end

  def build_inputs
    source = File.read(GRAMMAR_PATH)
    ast = Ibex::Frontend::Parser.new(source, file: "benchmark/grammars/representative.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    input = "#{File.read(INPUT_PATH)}\nlet benchmark_seed: Number = 12345;\n"
    [source, input, automaton]
  end

  def generated_source(automaton, variant)
    source = Ibex::Codegen::Ruby.new(automaton, table: :compact, line_convert: false).generate
    return source if variant == "table"

    inject_case_dispatch(source, automaton)
  end

  def inject_case_dispatch(source, automaton)
    tables = Ibex::Tables.build(automaton, format: :plain)
    actions = (tables.actions.flat_map(&:values) + tables.default_actions.compact + [[:error]]).uniq
    indexes = actions.each_with_index.to_h
    method_source = case_dispatch_method(tables, actions, indexes)
    marker = "  DEBUG_ENABLED = false\n"
    raise "generated debug marker changed" unless source.include?(marker)

    source.sub(marker, "#{method_source}\n#{marker}")
  end

  def case_dispatch_method(tables, actions, indexes)
    lines = [
      "  CASE_DISPATCH_ACTIONS = #{actions.inspect}.each(&:freeze).freeze",
      "  def action_for_current_state",
      "    read_lookahead if @lookahead.equal?(NO_LOOKAHEAD)",
      "    return CASE_DISPATCH_ACTIONS.fetch(#{indexes.fetch([:error])}) unless TOKEN_NAMES.key?(@lookahead)",
      "",
      "    case @state_stack.last"
    ]
    tables.actions.each_with_index do |row, state|
      lines << "    when #{state}"
      lines << "      case @lookahead"
      row.sort.each do |token, action|
        lines << "      when #{token} then CASE_DISPATCH_ACTIONS.fetch(#{indexes.fetch(action)})"
      end
      default = tables.default_actions.fetch(state)
      fallback = indexes.fetch(default || [:error])
      lines << "      else CASE_DISPATCH_ACTIONS.fetch(#{fallback})"
      lines << "      end"
    end
    lines.push(
      "    else CASE_DISPATCH_ACTIONS.fetch(#{indexes.fetch([:error])})",
      "    end",
      "  end",
      "  private :action_for_current_state"
    )
    lines.join("\n")
  end

  def chain_rule_audit
    _source, _input, automaton = build_inputs
    grammar = automaton.grammar
    nonterminal_ids = grammar.nonterminals.map(&:id)
    units = grammar.productions.select do |production|
      production.rhs.length == 1 && nonterminal_ids.include?(production.rhs.first)
    end
    {
      productions: grammar.productions.length,
      unit_productions: units.length,
      actionless_unit_productions: units.count { |production| production.action.nil? },
      action_unit_productions: units.count { |production| !production.action.nil? }
    }
  end

  def assert_equivalent!(variants)
    keys = %w[source_sha256 automaton_sha256 result_sha256]
    keys.each do |key|
      values = variants.values.flatten.map { |entry| entry.fetch(key) }.uniq
      raise "#{key} differs across candidates" unless values.length == 1
    end
    variants.each_value do |observations|
      structures = observations.map { |entry| entry.except("runtime_ms") }.uniq
      raise "candidate structure changed between runs" unless structures.one?
    end
  end

  def environment
    {
      ruby_engine: RUBY_ENGINE,
      ruby_version: RUBY_VERSION,
      ruby_platform: RUBY_PLATFORM,
      host_os: RbConfig::CONFIG.fetch("host_os"),
      host_cpu: RbConfig::CONFIG.fetch("host_cpu")
    }
  end

  def median(values)
    sorted = values.sort
    middle = sorted.length / 2
    sorted.length.odd? ? sorted.fetch(middle) : ((sorted.fetch(middle - 1) + sorted.fetch(middle)) / 2.0)
  end

  def percentage(delta, baseline)
    ((delta.to_f / baseline) * 100).round(3)
  end
end
# rubocop:enable Metrics/ModuleLength

OptimizationCandidates.run(ARGV) if $PROGRAM_NAME == __FILE__
