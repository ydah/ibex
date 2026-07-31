# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "open3"
require "tmpdir"
require "uri"
require_relative "../../lib/ibex"

module Ibex
  module Quality
    # Downloads pinned public grammar inputs into a temporary directory and
    # publishes only aggregate compatibility evidence.
    class BisonExternal
      MAX_DOWNLOAD_BYTES = 2 * 1024 * 1024
      BISON_CORPUS = [
        {
          name: "gnu-bison-calc",
          url: "https://raw.githubusercontent.com/akimd/bison/" \
               "25b3d0e1a3f97a33615099e4b211f3953990c203/examples/c/calc/calc.y",
          sha256: "59259755e8619ebb514b1c1832de28574341efbb64f3f593318961c0cfa4aa1b",
          expected: { rules: 5, actions: 7, unsupported: 1, productions: 13, states: 22, sr: 0, rr: 0 }
        },
        {
          name: "jq",
          url: "https://raw.githubusercontent.com/jqlang/jq/" \
               "603db3f57741d217ba651e61086b550a72148b83/src/parser.y",
          sha256: "803aa7c0b1acba2228e52d1de392fb51e60a7bbe23e42870aea1d62c43360c60",
          expected: { rules: 29, actions: 167, unsupported: 1, productions: 167, states: 311, sr: 408, rr: 0 }
        },
        {
          name: "php",
          url: "https://raw.githubusercontent.com/php/php-src/" \
               "7b78eb4fcc29c5cafa083c667558d0fe79c0c499/Zend/zend_language_parser.y",
          sha256: "afb7ad325d4bd7ca4bb037c96dd31e8afdd0652469f0248cc4139a475f0d5e98",
          expected: { rules: 177, actions: 552, unsupported: 1, productions: 635, states: 1203, sr: 0, rr: 0 }
        },
        {
          name: "postgresql",
          url: "https://raw.githubusercontent.com/postgres/postgres/" \
               "d6eac691747499645f21398c9e305d7a671e0229/src/backend/parser/gram.y",
          sha256: "649da7c47a4d4a26062e9acde2c588ac796a3b74a94079649dd6d16c53a717fe",
          expected: { rules: 795, actions: 2436, unsupported: 3, productions: 3640, states: 6942, sr: 0, rr: 0 }
        },
        {
          name: "ruby-bison-era",
          url: "https://raw.githubusercontent.com/ruby/ruby/" \
               "e51014f9c05aa65cbf203442d37fef7c12390015/parse.y",
          sha256: "cd9d083728abb271d24241347623c91d7e2bac2d063331938afc8fcad312b555",
          expected: { rules: 223, actions: 594, unsupported: 2, productions: 781, states: 1303, sr: 0, rr: 0 }
        }
      ].freeze
      CURRENT_RUBY = {
        name: "ruby-current-lrama",
        url: "https://raw.githubusercontent.com/ruby/ruby/" \
             "825c457945cdb0d07c6075846dc778b147224cbf/parse.y",
        sha256: "90ff67d6f610bacc24439dfac6c1c30ed9eb08aa8b80225c0f074947f1894bb5",
        expected: {
          rules: 231, actions: 486, unsupported: 23, structural_unsupported: 22,
          productions: 695, states: 1152, sr: 27, rr: 0
        }
      }.freeze

      # @rbs () -> void
      def run!
        results = BISON_CORPUS.map { |entry| validate_entry(entry) }
        current = validate_current_ruby
        comparison = compare_ruby_with_bison(results)
        puts JSON.pretty_generate(
          schema_version: 1,
          result: "compatible",
          bison_grammars: results,
          current_ruby_analysis: current,
          ruby_bison_comparison: comparison,
          statement: "Downloaded grammar source is temporary; output contains aggregate evidence only."
        )
      end

      private

      # @rbs (Hash[Symbol, untyped] entry) -> Hash[Symbol, untyped]
      def validate_entry(entry)
        source = verified_source(entry)
        measurement, result, = measure(source, entry.fetch(:name))
        expected = entry.fetch(:expected)
        raise "#{entry.fetch(:name)} compatibility changed: #{measurement.inspect}" unless measurement == expected
        raise "#{entry.fetch(:name)} unexpectedly has structural gaps" unless result.structurally_complete?

        { name: entry.fetch(:name), sha256: entry.fetch(:sha256) }.merge(measurement)
      end

      # @rbs () -> Hash[Symbol, untyped]
      def validate_current_ruby
        source = verified_source(CURRENT_RUBY)
        measurement, result, automaton = measure(source, CURRENT_RUBY.fetch(:name))
        measurement[:structural_unsupported] = result.structural_unsupported.length
        expected = CURRENT_RUBY.fetch(:expected)
        raise "current Ruby analysis changed: #{measurement.inspect}" unless measurement == expected
        raise "current Ruby parse.y must expose structural gaps" if result.structurally_complete?

        explanation = Codegen::Explain.new(
          automaton, state: 413, max_tokens: 8, max_configurations: 10_000
        ).to_h
        unless explanation.dig(:summary, :matched_conflicts) == 1
          raise "current Ruby selected explanation did not retain its conflict"
        end

        {
          name: CURRENT_RUBY.fetch(:name),
          sha256: CURRENT_RUBY.fetch(:sha256),
          structurally_complete: false,
          structural_directives: result.structural_unsupported.map(&:name).uniq.sort,
          explanation: {
            state: 413,
            matched_conflicts: 1,
            witness_kind: explanation.dig(:conflicts, 0, :witness, :kind)
          }
        }.merge(measurement)
      end

      # @rbs (String source, String name) ->
      #   [Hash[Symbol, Integer], BisonImport::Result, IR::Automaton]
      def measure(source, name)
        result = BisonImport::Importer.new(source, file: "#{name}.y").run
        ast = Frontend::Parser.new(result.source, file: "#{name}.ibex.y", mode: :extended).parse
        grammar = Normalizer.new(ast, mode: :extended).normalize
        automaton = LALR::Builder.new(grammar).build
        measurement = {
          rules: result.rule_count,
          actions: result.actions.length,
          unsupported: result.to_h.dig(:counts, :unsupported_directives),
          productions: grammar.productions.length,
          states: automaton.states.length,
          sr: automaton.conflict_summary.fetch(:sr),
          rr: automaton.conflict_summary.fetch(:rr)
        }
        [measurement, result, automaton]
      end

      # @rbs (Array[Hash[Symbol, untyped]] results) -> Hash[Symbol, untyped]
      def compare_ruby_with_bison(results)
        entry = BISON_CORPUS.find { |item| item.fetch(:name) == "ruby-bison-era" }
        raise "missing Ruby Bison-era corpus entry" unless entry

        source = verified_source(entry)
        Dir.mktmpdir("ibex-bison-compare") do |directory|
          executable = ENV.fetch("BISON", "bison")
          bison_states = run_bison_comparison(executable, directory, source)
          ibex = results.find { |item| item.fetch(:name) == "ruby-bison-era" }
          raise "missing Ruby import measurement" unless ibex
          raise "unexpected GNU Bison Ruby state count #{bison_states}" unless bison_states == 1304

          {
            bison_version: bison_version(executable),
            bison_states: bison_states,
            ibex_states: ibex.fetch(:states),
            state_delta: ibex.fetch(:states) - bison_states,
            bison_productions: 781,
            ibex_productions: ibex.fetch(:productions),
            unresolved_shift_reduce: ibex.fetch(:sr),
            unresolved_reduce_reduce: ibex.fetch(:rr),
            explanation: "GNU Bison shifts end-of-input into a separate accept state; " \
                         "Ibex accepts on the completed start item."
          }
        end
      rescue Errno::ENOENT
        raise "GNU Bison executable is required for the external comparison"
      end

      # @rbs (String executable, String directory, String source) -> Integer
      def run_bison_comparison(executable, directory, source)
        input = File.join(directory, "parse.y")
        report = File.join(directory, "parse.output")
        generated = File.join(directory, "parse.c")
        File.binwrite(input, source.gsub(/\bRUBY_TOKEN\([^()\n]*\)/, ""))
        _stdout, stderr, status = Open3.capture3(
          executable, "--report=state", "--report-file=#{report}", "--output=#{generated}", input
        )
        raise "GNU Bison comparison failed: #{stderr}" unless status.success?

        File.binread(report).scan(/^State \d+$/).length
      end

      # @rbs (String executable) -> String
      def bison_version(executable)
        output, status = Open3.capture2(executable, "--version")
        raise "GNU Bison version query failed" unless status.success?

        output.lines.first.to_s.strip
      end

      # @rbs (Hash[Symbol, untyped] entry) -> String
      def verified_source(entry)
        source = cached_or_downloaded(entry)
        raise "#{entry.fetch(:name)} exceeds the external download byte limit" if
          source.bytesize > MAX_DOWNLOAD_BYTES

        actual = Digest::SHA256.hexdigest(source)
        raise "#{entry.fetch(:name)} checksum mismatch: #{actual}" unless actual == entry.fetch(:sha256)

        source
      end

      # @rbs (Hash[Symbol, untyped] entry) -> String
      def cached_or_downloaded(entry)
        cache = ENV.fetch("IBEX_BISON_EXTERNAL_CACHE", nil)
        return File.binread(File.join(cache, "#{entry.fetch(:name)}.y")) if cache

        uri = URI(entry.fetch(:url))
        response = Net::HTTP.start(
          uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60
        ) { |http| http.request(Net::HTTP::Get.new(uri)) }
        raise "#{entry.fetch(:name)} download failed with HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      end
    end
  end
end
