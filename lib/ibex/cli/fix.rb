# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require "optparse"
require_relative "../fix"

module Ibex
  # CLI entry point for bounded conflict-repair proposals.
  module CLIFix
    # @rbs!
    #   type fix_options = {
    #     paths: Array[String],
    #     algorithm: Symbol,
    #     mode: Symbol,
    #     format: String,
    #     max_candidates: Integer,
    #     max_builds: Integer,
    #     equiv_samples: Integer,
    #     equiv_max_tokens: Integer,
    #     equiv_max_configurations: Integer,
    #     ?state: Integer,
    #     ?conflict_index: Integer,
    #     ?messages: String,
    #     ?apply: String | true
    #   }
    #   private def normalize_grammar_path: (String) -> IR::Grammar
    #   private def activate_cli_feature: (Symbol) -> void

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_fix_command(arguments)
      settings = fix_options(arguments)
      paths = settings.fetch(:paths)
      raise Ibex::Error, "(fix):1:1: fix requires exactly one grammar source file" unless paths.length == 1

      path = paths.fetch(0)
      source, fixer = prepare_fixer(path, settings)
      report = fixer.run
      apply_fix!(path, source, report, fixer, settings.fetch(:apply)) if settings[:apply]
      write_fix_report(report, settings.fetch(:format))
      report.fetch(:proposals).empty? ? 1 : 0
    rescue Fix::BudgetExceeded => e
      report = { ibex_report: "fix", schema_version: 1 }.merge(e.details)
      write_fix_report(report, settings&.fetch(:format) || "json")
      2
    end

    # @rbs (String path, fix_options settings) -> [String, Fix]
    def prepare_fixer(path, settings)
      source = File.binread(path)
      grammar = normalize_grammar_path(path)
      automaton = LALR::Builder.new(grammar, algorithm: settings.fetch(:algorithm)).build
      message_file = settings[:messages]
      messages = ErrorMessages.load(message_file) if message_file
      fixer = Fix.new(
        source,
        file: path, grammar: grammar, automaton: automaton,
        algorithm: settings.fetch(:algorithm), mode: settings.fetch(:mode),
        state: settings[:state], conflict_index: settings[:conflict_index],
        max_candidates: settings.fetch(:max_candidates), max_builds: settings.fetch(:max_builds),
        equiv_samples: settings.fetch(:equiv_samples),
        equiv_max_tokens: settings.fetch(:equiv_max_tokens),
        equiv_max_configurations: settings.fetch(:equiv_max_configurations),
        messages: messages, message_file: message_file
      )
      [source, fixer]
    end

    # @rbs (Array[String] arguments) -> fix_options
    def fix_options(arguments)
      settings = {
        paths: [], algorithm: :lalr, mode: :default, format: "json",
        max_candidates: 32, max_builds: 32, equiv_samples: 100,
        equiv_max_tokens: 8, equiv_max_configurations: 50_000
      } #: fix_options
      parser = OptionParser.new do |options|
        options.banner = "Usage: ibex fix [options] GRAMMAR"
        add_fix_target_options(options, settings)
        add_fix_budget_options(options, settings)
        options.on("--algorithm=NAME", %w[slr lalr ielr lr1], "current construction algorithm") do |value|
          settings[:algorithm] = value.to_sym
        end
        options.on("--mode=MODE", %w[default extended], "grammar mode") do |value|
          settings[:mode] = value.to_sym
          @options[:mode] = value.to_sym
        end
        options.on("--apply[=ID]", "atomically apply one safe source proposal") do |value|
          settings[:apply] = value || true
        end
        options.on("--messages=FILE", "measure effects on an error-message catalog") do |value|
          settings[:messages] = value
        end
        options.on("--format=FORMAT", %w[json text], "json or text") { |value| settings[:format] = value }
      end
      settings[:paths] = parser.parse(arguments)
      settings
    end

    # @rbs (OptionParser options, fix_options settings) -> void
    def add_fix_target_options(options, settings)
      options.on("--state=N", Integer, "target state (default first unresolved conflict)") do |value|
        raise OptionParser::InvalidArgument, "--state must be nonnegative" if value.negative?

        settings[:state] = value
      end
      options.on("--conflict-index=N", Integer, "target conflict index within the state") do |value|
        raise OptionParser::InvalidArgument, "--conflict-index must be nonnegative" if value.negative?

        settings[:conflict_index] = value
      end
    end

    # @rbs (OptionParser options, fix_options settings) -> void
    def add_fix_budget_options(options, settings)
      {
        "max-candidates" => :max_candidates,
        "max-builds" => :max_builds,
        "equiv-samples" => :equiv_samples,
        "equiv-max-tokens" => :equiv_max_tokens,
        "equiv-max-configurations" => :equiv_max_configurations
      }.each do |name, key|
        options.on("--#{name}=N", Integer, "positive bounded-search limit") do |value|
          raise OptionParser::InvalidArgument, "--#{name} must be positive" unless value.positive?

          settings[key] = value
        end
      end
    end

    # @rbs (String path, String original, Hash[Symbol, untyped] report, Fix fixer, String | true selector) -> void
    def apply_fix!(path, original, report, fixer, selector)
      proposal = selected_fix_proposal(report.fetch(:proposals), selector)
      unless proposal.fetch(:applyable)
        raise Ibex::Error, "(fix):1:1: proposal #{proposal.fetch(:id)} changes invocation options, not source"
      end
      if File.symlink?(path) || File.stat(path).nlink > 1
        raise Ibex::Error, "(fix):1:1: --apply refuses symlink aliases and files with multiple hard links"
      end

      replacement = fixer.sources.fetch(proposal.fetch(:id))
      activate_cli_feature(:CLIFormatting)
      results = [{
        path: path, label: path, source: original, formatted: replacement
      }]
      targets = send(:formatting_targets, results)
      send(:transactionally_write_formatted, targets)
      report[:applied] = proposal.fetch(:id)
    end

    # @rbs (Array[Hash[Symbol, untyped]] proposals, String | true selector) -> Hash[Symbol, untyped]
    def selected_fix_proposal(proposals, selector)
      proposal = if selector == true
                   proposals.find { |entry| entry.fetch(:applyable) }
                 else
                   proposals.find { |entry| entry.fetch(:id) == selector }
                 end
      proposal || raise(Ibex::Error, "(fix):1:1: no matching applyable safe proposal")
    end

    # @rbs (Hash[Symbol, untyped] report, String format) -> void
    def write_fix_report(report, format)
      if format == "json"
        @stdout.puts(JSON.pretty_generate(report))
        return
      end

      @stdout.puts("result=#{report.fetch(:result)} proposals=#{report.fetch(:proposals, []).length}")
      report.fetch(:proposals, []).each do |proposal|
        @stdout.puts("#{proposal.fetch(:id)} #{proposal.fetch(:description)}")
      end
      @stdout.puts(report.fetch(:statement, Equiv::CAVEAT))
    end
  end
end
