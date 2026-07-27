# frozen_string_literal: true

require "optparse"

module BenchmarkSupport
  # Parses the intentionally diagnostic-only external profile command.
  module PublicProfileOptions
    DEFAULTS = {
      projects: nil,
      checkouts: {},
      runs: 1,
      warmup: 50,
      iterations: 10_000,
      interval_usec: 1_000,
      top_frames: 20,
      allow_dirty: false,
      output: nil
    }.freeze

    module_function

    def parse(arguments, manifest, root:)
      options = DEFAULTS.merge(projects: [], checkouts: {})
      option_parser(options).parse!(arguments)
      options[:projects] = manifest.ids if options[:projects].empty?
      validate!(options, manifest, root)
      options
    end

    # rubocop:disable Metrics/BlockLength -- the block is the complete profile CLI surface.
    def option_parser(options)
      OptionParser.new do |parser|
        parser.banner = "Usage: benchmark/public_profile.rb --checkout ID=PATH --output FILE [options]"
        parser.on("--checkout ID=PATH", "map a manifest workload to an exact checkout") do |value|
          identifier, path = value.split("=", 2)
          raise OptionParser::InvalidArgument, "checkout must use ID=PATH" unless identifier && path && !path.empty?

          options[:checkouts][identifier] = path
        end
        parser.on("--project ID", "select a workload; repeat to select multiple") do |value|
          options[:projects] << value
        end
        parser.on("--runs N", Integer, "fresh profile processes per scenario") { |value| options[:runs] = value }
        parser.on("--warmup N", Integer, "warm-up workloads before each runtime profile") do |value|
          options[:warmup] = value
        end
        parser.on("--runtime-iterations N", Integer, "profiled runtime workloads") do |value|
          options[:iterations] = value
        end
        parser.on("--interval-usec N", Integer, "StackProf wall-clock sampling interval") do |value|
          options[:interval_usec] = value
        end
        parser.on("--top-frames N", Integer, "summary frame count per raw profile") do |value|
          options[:top_frames] = value
        end
        parser.on("--allow-dirty", "diagnostics only; permit dirty root and checkouts") do
          options[:allow_dirty] = true
        end
        parser.on("--output FILE", "write diagnostic JSON and sibling raw profile directory") do |value|
          options[:output] = value
        end
      end
    end
    # rubocop:enable Metrics/BlockLength

    def validate!(options, manifest, root)
      unknown = options.fetch(:projects) - manifest.ids
      raise OptionParser::InvalidArgument, "unknown projects: #{unknown.join(', ')}" unless unknown.empty?
      raise OptionParser::InvalidArgument, "select at least one project" if options.fetch(:projects).empty?

      missing = options.fetch(:projects).reject { |identifier| options.fetch(:checkouts).key?(identifier) }
      raise OptionParser::MissingArgument, "--checkout is required for: #{missing.join(', ')}" unless missing.empty?
      raise OptionParser::MissingArgument, "--output is required" unless options[:output]

      validate_counts!(options)
      validate_output!(options.fetch(:output), root)
    end

    def validate_counts!(options)
      %i[runs iterations interval_usec top_frames].each do |key|
        value = options.fetch(key)
        raise OptionParser::InvalidArgument, "#{key} must be positive" unless value.is_a?(Integer) && value.positive?
      end
      raise OptionParser::InvalidArgument, "warmup must not be negative" if options.fetch(:warmup).negative?
    end

    def validate_output!(path, root)
      output = File.expand_path(path, root)
      formal_results = File.join(root, "benchmark/results")
      return unless output == formal_results || output.start_with?("#{formal_results}/")

      raise OptionParser::InvalidArgument, "diagnostic profiles must not be written under benchmark/results"
    end
  end
end
