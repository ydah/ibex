# frozen_string_literal: true

require "optparse"

module BenchmarkSupport
  # Parses and validates formal versus diagnostic public comparison settings.
  module PublicComparisonOptions
    module_function

    def parse(arguments, manifest, defaults)
      options = defaults.merge(projects: [], checkouts: {})
      option_parser(options).parse!(arguments)
      options[:projects] = manifest.ids if options[:projects].empty?
      apply_smoke_defaults!(options) if options[:smoke]
      validate!(options, manifest)
      options
    end

    def option_parser(options)
      OptionParser.new do |parser|
        parser.banner = "Usage: benchmark/public_comparison.rb --checkout ID=PATH [options]"
        add_checkout_options(parser, options)
        add_measurement_options(parser, options)
        add_execution_options(parser, options)
      end
    end

    def add_checkout_options(parser, options)
      parser.on("--checkout ID=PATH", "map a manifest workload to an exact checkout") do |value|
        identifier, path = value.split("=", 2)
        raise OptionParser::InvalidArgument, "checkout must use ID=PATH" unless identifier && path && !path.empty?

        options[:checkouts][identifier] = path
      end
      parser.on("--project ID", "select a workload; repeat to select multiple") { |value| options[:projects] << value }
    end

    def add_measurement_options(parser, options)
      parser.on("--runs N", Integer) { |value| options[:runs] = value }
      parser.on("--warmup N", Integer) { |value| options[:warmup] = value }
      parser.on("--runtime-iterations N", Integer) { |value| options[:iterations] = value }
      parser.on("--behavior-probe-iterations N", Integer) { |value| options[:probe_iterations] = value }
      parser.on("--bootstrap-samples N", Integer) { |value| options[:bootstrap_samples] = value }
    end

    def add_execution_options(parser, options)
      parser.on("--expected-racc-backend BACKEND", "native or ruby") { |value| options[:expected_racc_backend] = value }
      parser.on("--allow-dirty-checkouts", "diagnostics only; record checkout dirtiness") do
        options[:allow_dirty] = true
      end
      parser.on("--smoke", "one isolated diagnostic observation, never formal evidence") { options[:smoke] = true }
      parser.on("--output PATH") { |value| options[:output] = value }
    end

    def apply_smoke_defaults!(options)
      options[:runs] = 1
      options[:warmup] = 0
      options[:iterations] = 1
      options[:probe_iterations] = 2
      options[:bootstrap_samples] = 1_000
    end

    def validate!(options, manifest)
      unknown = options.fetch(:projects) - manifest.ids
      raise OptionParser::InvalidArgument, "unknown projects: #{unknown.join(', ')}" unless unknown.empty?
      raise OptionParser::InvalidArgument, "select at least one project" if options.fetch(:projects).empty?

      validate_measurements!(options)
      validate_execution!(options)
    end

    def validate_measurements!(options)
      unless options.fetch(:smoke) || options.fetch(:runs) >= 10
        raise OptionParser::InvalidArgument, "formal reports require at least ten isolated runs"
      end
      raise OptionParser::InvalidArgument, "runs must be positive" unless options.fetch(:runs).positive?
      raise OptionParser::InvalidArgument, "warmup must not be negative" if options.fetch(:warmup).negative?
      unless options.fetch(:iterations).positive?
        raise OptionParser::InvalidArgument, "runtime iterations must be positive"
      end
      raise OptionParser::InvalidArgument, "probe iterations must be between 1 and 100" unless
        (1..100).cover?(options.fetch(:probe_iterations))
      raise OptionParser::InvalidArgument, "bootstrap samples must be at least 1000" if
        options.fetch(:bootstrap_samples) < 1_000
    end

    def validate_execution!(options)
      if options.fetch(:allow_dirty) && !options.fetch(:smoke)
        raise OptionParser::InvalidArgument, "dirty checkouts are allowed only with --smoke"
      end

      backend = options.fetch(:expected_racc_backend)
      unless %w[native ruby].include?(backend)
        raise OptionParser::InvalidArgument, "expected Racc backend must be native or ruby"
      end

      return if options.fetch(:smoke) || backend == "native"

      raise OptionParser::InvalidArgument, "formal reports require Racc's native backend"
    end
  end
end
