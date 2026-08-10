# frozen_string_literal: true
# rbs_inline: enabled

require_relative "../watch"
require_relative "../generation_transaction"

module Ibex
  # Long-running CLI generation over stable source snapshots.
  module CLIWatch
    # @rbs!
    #   private def process_grammar: (String) -> Integer
    #   private def generation_artifacts: () -> ArtifactSet
    #   private def report_status: (String) -> void

    # Rendered watch generation awaiting its stability-guarded publication.
    class Build
      attr_reader :artifacts #: ArtifactSet
      attr_reader :statuses #: Array[String]
      attr_reader :source_paths #: Array[String]
      attr_reader :attempted_paths #: Array[String]
      attr_reader :source_records #: Array[GenerationInput]

      # rubocop:disable Layout/LineLength
      # @rbs (artifacts: ArtifactSet, statuses: Array[String], source_paths: Array[String], attempted_paths: Array[String], source_records: Array[GenerationInput]) -> void
      def initialize(artifacts:, statuses:, source_paths:, attempted_paths:, source_records:)
        @artifacts = artifacts
        @statuses = statuses.freeze
        @source_paths = source_paths.freeze
        @attempted_paths = attempted_paths.freeze
        @source_records = source_records.freeze
        freeze
      end
      # rubocop:enable Layout/LineLength
    end

    private

    # @rbs (String path) -> Integer
    def run_watch(path)
      raise Ibex::Error, "(cli):1:1: --watch requires a grammar file, not stdin" if path == "-"

      paths = [path]
      paths << @options[:messages] if @options[:messages]
      Watch::Runner.new(
        paths: paths,
        build: -> { prepare_watch_generation(path) },
        publish: ->(build, snapshot, continue) { publish_watch_generation(build, snapshot, continue) },
        failure_paths: -> { watch_failure_paths(path) },
        stderr: @stderr,
        clock: @watch_clock,
        sleeper: @watch_sleeper,
        iteration_hook: @watch_iteration_hook
      ).run
    end

    # @rbs (String path) -> Build
    def prepare_watch_generation(path)
      @defer_generation_publication = true
      status = process_grammar(path)
      raise Ibex::Error, "(watch):1:1: generation returned status #{status}" unless status.zero?

      Build.new(
        artifacts: generation_artifacts,
        statuses: @generation_statuses.dup,
        source_paths: @generation_sources.dup,
        attempted_paths: @last_resolver&.attempted_paths || [],
        source_records: @generation_inputs.dup
      )
    ensure
      @defer_generation_publication = false
    end

    # @rbs (Watch::_BuildResult build, Watch::SourceSnapshot snapshot, ^() -> bool continue) -> void
    def publish_watch_generation(build, snapshot, continue)
      typed_build = build #: Build
      stable = lambda do
        continue.call && typed_build.source_records.all?(&:current?) &&
          Watch::SourceSnapshot.new(snapshot.paths) == snapshot
      end
      GenerationTransaction.new(
        typed_build.artifacts,
        warning: ->(message) { @stderr.puts("ibex: warning: #{message}") },
        stability_check: stable,
        source_records: typed_build.source_records,
        lock_sleeper: @watch_sleeper
      ).commit
      typed_build.statuses.each { |message| report_status(message) }
    end

    # @rbs (String path) -> Array[String]
    def watch_failure_paths(path)
      paths = [path]
      paths << @options[:messages] if @options[:messages]
      paths.concat(@last_resolver.attempted_paths) if @last_resolver
      unless @generation_artifacts.nil?
        generation_artifacts.each do |artifact|
          paths << artifact.path
          paths << File.dirname(artifact.path)
        end
      end
      paths.compact
    end
  end
end
