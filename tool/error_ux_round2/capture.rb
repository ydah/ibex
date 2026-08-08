# frozen_string_literal: true

require "digest"
require "json"
require_relative "../../lib/ibex"
require_relative "case_runner"
require_relative "implementation_closure"
require_relative "policy"

module Ibex
  module ErrorUXRound2
    ROOT = File.expand_path("../..", __dir__)
    CORPUS = File.join(ROOT, "test/fixtures/error_ux_round2/corpus-v1.json")
    EVIDENCE = File.join(ROOT, "docs/error-ux-round2-v1.json")
    R001_SNAPSHOT = File.join(ROOT, "test/fixtures/error_ux/json-errors-v1.json")
    R001_SNAPSHOT_SHA256 = "bf49b2f8ba5329f1984d6e90e4b170b5811f4c800536fca56eba1f2725189dbf"
    FIXTURE_CLASSES = {
      "test/fixtures/error_ux_round2/delimiters.y" => %i[ErrorUXRound2 DelimiterParser],
      "test/fixtures/error_ux_round2/statements.y" => %i[ErrorUXRound2 StatementParser],
      "test/fixtures/error_ux_round2/stateful_strings.y" => %i[ErrorUXRound2 StatefulStringParser],
      "test/fixtures/error_ux_round2/unknown_token.y" => %i[ErrorUXRound2 UnknownTokenParser]
    }.freeze
    REQUIRED_DIMENSIONS = Policy::REQUIRED_DIMENSIONS
    # Builds the committed repository observation without changing R001.
    class Capture
      def initialize(root: ROOT)
        @root = File.expand_path(root)
        @parser_classes = {}
      end

      def build
        definitions = corpus.fetch("cases")
        {
          "ibex_error_ux_round2" => "repository-capture",
          "schema_version" => 1,
          "repository_capture" => repository_capture(definitions),
          "problem" => Policy.problem,
          "semantics" => Policy.semantics,
          "trust_boundary" => Policy.trust_boundary,
          "external_subjective_gate" => Policy.external_subjective_gate,
          "limitations" => Policy.limitations,
          "kill_conditions" => Policy.kill_conditions,
          "cases" => definitions.map { |definition| case_document(definition) }
        }
      end

      def render
        "#{JSON.pretty_generate(build)}\n"
      end

      def implementation_sources
        @implementation_sources ||= ImplementationClosure.new(root: @root).paths.map do |path|
          { "path" => path, "sha256" => sha256(File.binread(File.join(@root, path))) }
        end.freeze
      end

      private

      def corpus
        @corpus ||= JSON.parse(File.binread(File.join(@root, relative(CORPUS))))
      end

      def repository_capture(definitions)
        r001_digest = sha256(File.binread(File.join(@root, relative(R001_SNAPSHOT))))
        unless r001_digest == R001_SNAPSHOT_SHA256
          raise "R001 normative snapshot changed: expected #{R001_SNAPSHOT_SHA256}, got #{r001_digest}"
        end

        {
          "status" => "complete",
          "generator" => "tool/error_ux_round2.rb",
          "corpus" => {
            "path" => "test/fixtures/error_ux_round2/corpus-v1.json",
            "sha256" => sha256(File.binread(File.join(@root, relative(CORPUS))))
          },
          "implementation_sources" => implementation_sources,
          "case_count" => definitions.length,
          "deterministic_regeneration" => true,
          "r001_normative_snapshot" => {
            "path" => "test/fixtures/error_ux/json-errors-v1.json",
            "sha256" => r001_digest,
            "expected_sha256" => R001_SNAPSHOT_SHA256,
            "status" => "unchanged"
          }
        }
      end

      def case_document(definition)
        path = definition.fetch("grammar")
        fixture = File.binread(File.join(@root, path))
        CaseRunner.new(definition, parser_class(path, fixture)).build.merge(
          "grammar_sha256" => sha256(fixture)
        )
      end

      def parser_class(path, source)
        @parser_classes[path] ||= begin
          constants = FIXTURE_CLASSES.fetch(path) { raise "untrusted H003 fixture path: #{path}" }
          ast = Frontend::Parser.new(source, file: path).parse
          grammar = Normalizer.new(ast).normalize
          automaton = LALR::Builder.new(grammar).build
          generated = Codegen::Ruby.new(automaton, table: :compact, line_convert: false).generate
          namespace = Module.new
          namespace.module_eval(generated, "(generated-h003:#{path})")
          constants.reduce(namespace) { |scope, name| scope.const_get(name, false) }
        end
      end

      def relative(path)
        path.delete_prefix("#{ROOT}/")
      end

      def sha256(bytes)
        Digest::SHA256.hexdigest(bytes.b)
      end
    end
  end
end
