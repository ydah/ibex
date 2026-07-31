# frozen_string_literal: true
# rbs_inline: enabled

require "digest"
require "fileutils"
require "json"

module Ibex
  # @rbs!
  #   type fuzz_external_description = {
  #     command: String,
  #     target_runtime: String,
  #     timeout_seconds: Integer,
  #     max_output_bytes: Integer,
  #     host_ruby_engine: String,
  #     host_ruby_version: String,
  #     host_platform: String
  #   }
  #   type fuzz_external_target = [
  #     ^(Array[String]) -> Symbol,
  #     fuzz_external_description
  #   ]

  # Automatic bounded minimization and persistence for fuzz differences.
  module CLIFuzzRegressions
    # @rbs!
    #   private def atomic_write_ir: (String path, String source) -> void

    private

    # @rbs (Fuzz fuzzer, Fuzz::Mismatch mismatch, String grammar_path,
    #   fuzz_external_target? external) -> Integer
    def write_minimized_fuzz_mismatch(fuzzer, mismatch, grammar_path, external)
      details = minimized_fuzz_mismatch(fuzzer, mismatch, grammar_path, external)
      report = {
        ibex_report: "fuzz", schema_version: 1, result: "difference", mismatch: details
      } #: Hash[Symbol, untyped]
      report[:external] = external[1] if external
      write_fuzz_report(report)
      1
    end

    # @rbs (Hash[Symbol, untyped] report) -> void
    def write_fuzz_report(report)
      if @options.fetch(:fuzz_format, "json") == "json"
        @stdout.puts JSON.pretty_generate(report)
        return
      end

      @stdout.puts("result=#{report.fetch(:result)}")
      case report.fetch(:result)
      when "no_difference_within_bounds"
        @stdout.puts("seed=#{report.fetch(:seed)} bounds=#{report.fetch(:bounds).inspect}")
        @stdout.puts("no difference found within the declared bounds; this is not a proof of equivalence")
      when "difference"
        mismatch = report.fetch(:mismatch)
        @stdout.puts("kind=#{mismatch.fetch(:kind)} tokens=#{mismatch.fetch(:tokens).inspect}")
        @stdout.puts("minimized=#{mismatch.fetch(:minimized_tokens).inspect} " \
                     "reduction_complete=#{mismatch.dig(:reduction, :complete)}")
        @stdout.puts("regression=#{mismatch.dig(:regression, :path)}") if mismatch[:regression]
      when "budget_exhausted"
        @stdout.puts("search incomplete: #{report.dig(:budget, :message)}")
      end
      external = report[:external] #: fuzz_external_description?
      return unless external

      @stdout.puts("target_runtime=#{external.fetch(:target_runtime)}")
      @stdout.puts("target_command=#{external.fetch(:command)}")
    end

    # @rbs (Fuzz::BudgetExceeded error,
    #   fuzz_external_target? external, phase: String) -> Integer
    def write_fuzz_budget_report(error, external, phase:)
      report = {
        ibex_report: "fuzz", schema_version: 1, result: "budget_exhausted",
        budget: error.details.merge(phase: phase)
      } #: Hash[Symbol, untyped]
      report[:external] = external[1] if external
      write_fuzz_report(report)
      2
    end

    # @rbs (Fuzz fuzzer, Fuzz::Mismatch mismatch, String grammar_path,
    #   fuzz_external_target? external) -> Hash[Symbol, untyped]
    def minimized_fuzz_mismatch(fuzzer, mismatch, grammar_path, external)
      result = fuzzer.minimize(
        mismatch, max_trials: @options.fetch(:fuzz_max_reduction_trials, 1_000)
      )
      details = mismatch.details.dup #: untyped
      details[:minimized_tokens] = result.items
      details[:reduction] = {
        original_size: result.original_size, minimized_size: result.items.length,
        trials: result.trials, complete: result.complete
      }
      regression = persist_fuzz_regression(
        mismatch.details, result, grammar_path, external&.[](1)
      )
      details[:regression] = regression if regression
      details
    end

    # @rbs (fuzz_mismatch mismatch, DeltaReducer::Result result, String grammar_path,
    #   fuzz_external_description? external) -> Hash[Symbol, String]?
    def persist_fuzz_regression(mismatch, result, grammar_path, external)
      return if @options.fetch(:fuzz_save_regression, true) == false

      directory = @options.fetch(:fuzz_regression_dir, "test/fuzz/regressions")
      FileUtils.mkdir_p(directory)
      document = fuzz_regression_document(mismatch, result, grammar_path, external)
      source = "#{JSON.pretty_generate(document)}\n"
      digest = Digest::SHA256.hexdigest(source)
      seed = @options.fetch(:fuzz_seed, 0)
      path = File.join(directory, "fuzz-seed-#{seed}-#{digest.slice(0, 16)}.json")
      validate_fuzz_regression_target!(path)
      atomic_write_ir(path, source)
      { path: path, sha256: digest }
    end

    # @rbs (String path) -> void
    def validate_fuzz_regression_target!(path)
      return unless File.symlink?(path) || (File.exist?(path) && File.stat(path).nlink > 1)

      raise Ibex::Error, "(fuzz):1:1: regression output refuses symlinks and files with multiple hard links"
    end

    # @rbs (fuzz_mismatch mismatch, DeltaReducer::Result result, String grammar_path,
    #   fuzz_external_description? external) -> Hash[Symbol, untyped]
    def fuzz_regression_document(mismatch, result, grammar_path, external)
      document = {
        ibex_report: "fuzz-regression", schema_version: 1, grammar: grammar_path,
        seed: @options.fetch(:fuzz_seed, 0), kind: mismatch[:kind],
        sentence: mismatch[:sentence],
        algorithms: mismatch[:outcomes].keys.reject { |name| name == :external }.map(&:to_s),
        original_tokens: mismatch[:tokens], minimized_tokens: result.items,
        bounds: mismatch[:bounds],
        reduction: {
          original_size: result.original_size, minimized_size: result.items.length,
          trials: result.trials, complete: result.complete
        }
      } #: Hash[Symbol, untyped]
      document[:external] = external if external
      document
    end
  end
end
