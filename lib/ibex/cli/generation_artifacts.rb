# frozen_string_literal: true
# rbs_inline: enabled

require_relative "../artifact_set"
require_relative "../generation_input"
require_relative "../generation_transaction"

module Ibex
  # Collects, verifies, and transactionally publishes CLI generation outputs.
  module CLIGenerationArtifacts
    # @rbs!
    #   private def report_status: (String) -> void
    #   private def verify_file: (String, String, String) -> void
    #   private def default_output_path: (String, String) -> String
    #   private def configuration_value: (String) -> untyped
    #   private def effective_configuration: () -> Configuration::Resolver

    private

    # @rbs () -> void
    def begin_artifact_generation
      @generation_artifacts = ArtifactSet.new
      @generation_statuses = [] #: Array[String]
      @generation_sources = [] #: Array[String]
      @generation_inputs = [] #: Array[GenerationInput]
      @generation_automaton = nil
    end

    # @rbs (Symbol kind, String path, String content, ?mode: Integer?, ?status: bool) -> Artifact
    def register_artifact(kind, path, content, mode: nil, status: false)
      artifact = generation_artifacts.add(kind: kind, path: path, content: content, mode: mode)
      @generation_statuses << "wrote #{path}" if status
      artifact
    end

    # @rbs (Array[String] source_paths) -> Integer
    def finish_artifact_generation(_source_paths)
      add_generation_manifest if @options[:manifest]
      return 0 if @defer_generation_publication

      ensure_generation_inputs_stable!
      if @options[:verify_output]
        verify_artifact_generation
        ensure_generation_inputs_stable!
      elsif !generation_artifacts.empty?
        GenerationTransaction.new(
          generation_artifacts,
          warning: ->(message) { @stderr.puts("ibex: warning: #{message}") },
          stability_check: -> { generation_inputs_stable? },
          source_records: @generation_inputs
        ).commit
        @generation_statuses.each { |message| report_status(message) }
      end
      0
    end

    # @rbs () -> void
    def add_generation_manifest
      require_relative "../generation_manifest"

      path = manifest_output_path
      source = GenerationManifest.render(
        generation_artifacts,
        source_records: @generation_inputs,
        options: generation_manifest_options
      )
      register_artifact(:manifest, path, source, status: true)
    end

    # @rbs () -> void
    def verify_artifact_generation
      generation_artifacts.each do |artifact|
        verify_file(artifact.path, artifact.content, artifact_label(artifact.kind))
      end
      parser = generation_artifacts.find { |artifact| artifact.kind == :parser }
      report_status("verified #{parser.path}") if parser
    end

    # @rbs (Symbol kind) -> String
    def artifact_label(kind)
      {
        parser: "parser",
        rbs: "RBS signature",
        action_source: "action source",
        manifest: "generation manifest"
      }.fetch(kind, kind.to_s.tr("_", " "))
    end

    # @rbs () -> ArtifactSet
    def generation_artifacts
      @generation_artifacts || raise(Ibex::Error, "(generation):1:1: artifact collection is not active")
    end

    # @rbs () -> bool
    def generation_inputs_stable?
      @generation_inputs.all?(&:current?)
    end

    # @rbs () -> void
    def ensure_generation_inputs_stable!
      return if generation_inputs_stable?

      raise GenerationTransaction::SourceChanged, "(generation):1:1: source changed while rendering outputs"
    end

    # @rbs (String path, String source) -> GenerationInput
    def record_generation_input(path, source)
      input = GenerationInput.new(path, source)
      @generation_inputs.reject! { |entry| entry.path == input.path }
      @generation_inputs << input
      @generation_sources = @generation_inputs.map(&:path)
      input
    end

    # @rbs () -> String
    def manifest_output_path
      configured = @options[:manifest]
      return configured if configured.is_a?(String) && !configured.empty?

      parser = generation_artifacts.find { |artifact| artifact.kind == :parser }
      raise Ibex::Error, "(generation):1:1: generation manifest requires a parser artifact" unless parser

      default_output_path(parser.path, ".ibex.json")
    end

    # @rbs () -> Hash[String, untyped]
    def generation_manifest_options
      keys = %i[
        action_source algorithm counterexample_max_configurations counterexample_max_tokens debug
        embedded emit entry_isolation executable frozen line_convert line_convert_all messages mode omit_actions rbs
        superclass table
      ]
      options = {} #: Hash[String, untyped]
      keys.each do |key|
        value = @options[key]
        options[key.to_s] = value unless value.nil?
      end
      options["cst_trivia"] = effective_cst_trivia.to_s
      append_ir_manifest_options(options)
      options
    end

    # @rbs (Hash[String, untyped] options) -> void
    def append_ir_manifest_options(options)
      automaton = @generation_automaton
      return unless automaton && automaton.schema_version >= 3

      grammar = automaton.grammar
      contract = grammar.parser_contract || raise("Grammar IR v3 parser contract is missing")
      options["grammar_ir"] = {
        "schema_version" => grammar.schema_version,
        "digest" => automaton.grammar_digest,
        "parser_contract" => stringify_contract(contract)
      }
      options["automaton_ir"] = {
        "schema_version" => automaton.schema_version,
        "algorithm" => automaton.algorithm,
        "entry_construction" => automaton.entry_construction,
        "construction_authority" => construction_authority
      }
      options["effective_configuration"] = manifest_effective_configuration
    end

    # @rbs () -> String
    def construction_authority
      @options[:from] == "automaton-ir" ? "embedded_automaton" : "grammar_contract"
    end

    # @rbs () -> Array[Hash[String, untyped]]
    def manifest_effective_configuration
      values = effective_configuration.to_h.fetch("configuration")
      return values unless @options[:from] == "automaton-ir"

      values.reject { |entry| %w[parser.algorithm parser.entries].include?(entry.fetch("key")) }
    end

    # @rbs (IR::ParserContract contract) -> Hash[String, untyped]
    def stringify_contract(contract)
      contract.to_h.to_h do |name, entry|
        [name.to_s, entry.to_h { |key, value| [key.to_s, value] }]
      end
    end

    # @rbs () -> Symbol
    def effective_cst_trivia
      configuration_value("cst.trivia")
    end
  end
end
