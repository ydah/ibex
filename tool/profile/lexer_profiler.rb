# frozen_string_literal: true

require "digest"
require "stringio"

module Ibex
  module Profile
    # Process-local probe for the current generated lexer's streaming buffer.
    # It is installed only by the diagnostic profiler and does not alter match
    # selection, actions, or source consumption.
    module LexerInputBufferProbe
      attr_reader :profile_peak_buffer_bytes

      def initialize(...)
        super
        @profile_peak_buffer_bytes = buffer.bytesize
      end

      def read_more?
        result = super
        record_profile_buffer_peak
        result
      end

      def consume(prefix)
        record_profile_buffer_peak
        super
      ensure
        record_profile_buffer_peak
      end

      private

      def record_profile_buffer_peak
        current = buffer.bytesize
        @profile_peak_buffer_bytes = current if current > (@profile_peak_buffer_bytes || 0)
      end
    end

    # Profiles the existing Ruby Regexp generated lexer without proposing or
    # executing an automaton replacement.
    class LexerProfiler
      def initialize(clock: nil, allocation_counter: nil)
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @allocation_counter = allocation_counter || method(:total_allocated_objects)
        install_buffer_probe
      end

      def profile(grammar:, input:, streaming:, incremental:, file:)
        parser_class = build_parser(grammar, file)
        tokens = []
        parser_class.prepend(token_probe(tokens))
        parser = parser_class.new
        source = streaming ? StringIO.new(input) : input
        before_allocations = @allocation_counter.call
        started = @clock.call
        parser.parse(source, file: file)
        elapsed = @clock.call - started
        allocations = @allocation_counter.call - before_allocations

        {
          "structure" => structure(grammar),
          "token_lengths" => token_lengths(tokens),
          "streaming" => streaming_observation(parser, streaming),
          "runtime_observations" => runtime_observations(elapsed, allocations),
          "incremental_full_scan" => incremental_observation(
            parser_class, grammar, input, incremental
          )
        }
      end

      private

      # JRuby does not expose CRuby's total_allocated_objects statistic. The
      # allocation observation is diagnostic-only, so an unavailable counter
      # must degrade to a stable zero rather than aborting the profile run.
      def total_allocated_objects
        statistics = GC.stat
        statistics[:total_allocated_objects] || statistics["total_allocated_objects"] || 0
      end

      def install_buffer_probe
        input = Runtime::LexerInput
        input.prepend(LexerInputBufferProbe) unless input.ancestors.include?(LexerInputBufferProbe)
      end

      def build_parser(grammar, file)
        automaton = LALR::Builder.new(grammar).build
        generated = Codegen::Ruby.new(automaton).generate
        namespace = Module.new
        namespace.module_eval(generated, file)
        grammar.class_name.split("::").reduce(namespace) { |scope, name| scope.const_get(name, false) }
      end

      def token_probe(tokens)
        Module.new do
          define_method(:next_token) do
            token = super()
            external, _value, location = token
            unless external.nil? || external == false
              tokens << {
                "token" => external.to_s,
                "bytes" => location.fetch(:end_byte) - location.fetch(:start_byte),
                "state" => location.fetch(:ibex_lexer_start_state).to_s
              }
            end
            token
          end
        end
      end

      def structure(grammar)
        lexer = grammar.lexer || raise(ArgumentError, "lexer profile requires a generated lexer")
        parser_mutations = parser_state_mutations(grammar)
        {
          "states" => lexer.states,
          "rules_per_state" => rules_per_state(lexer),
          "rule_count" => lexer.rules.length,
          "alternation_rule_ids" => lexer.rules.filter_map { |rule| rule.id if alternation?(rule.pattern) },
          "lazy_rule_ids" => lexer.rules.filter_map { |rule| rule.id if lazy_quantifier?(rule.pattern) },
          "arbitrary_lexer_action_rule_ids" => lexer.rules.filter_map { |rule| rule.id if rule.action },
          "state_mutation_sources" => {
            "lexer_rule_ids" => lexer_state_mutations(lexer),
            "parser_production_ids" => parser_mutations
          },
          "parser_to_lexer_feedback" => !parser_mutations.empty?,
          "regexp_warnings" => lexer.warnings.map do |warning|
            { "type" => warning.fetch(:type).to_s, "rule_id" => warning.fetch(:rule) }
          end
        }
      end

      def rules_per_state(lexer)
        lexer.states.to_h { |state| [state, lexer.rules.count { |rule| rule.state == state }] }
      end

      def lexer_state_mutations(lexer)
        lexer.rules.filter_map { |rule| rule.id if state_mutation?(rule.action) }
      end

      def parser_state_mutations(grammar)
        grammar.productions.filter_map do |production|
          production.id if state_mutation?(production.action&.code)
        end
      end

      def state_mutation?(source)
        source&.match?(/\blexer_state\s*=/) || false
      end

      def alternation?(pattern)
        pattern.match?(/(?<!\\)\|/)
      end

      def lazy_quantifier?(pattern)
        pattern.match?(/(?:[+*?]|\{\d+(?:,\d*)?\})\?/)
      end

      def token_lengths(tokens)
        lengths = tokens.map { |token| token.fetch("bytes") }
        {
          "count" => lengths.length,
          "minimum_bytes" => lengths.min,
          "maximum_bytes" => lengths.max,
          "total_bytes" => lengths.sum,
          "sequence_sha256" => Digest::SHA256.hexdigest(lengths.pack("Q>*")),
          "sample" => tokens.first(16)
        }
      end

      def streaming_observation(parser, streaming)
        input = parser.instance_variable_get(:@lexer_input)
        {
          "source_kind" => streaming ? "io" : "string",
          "chunk_size_bytes" => Runtime::LexerInput::DEFAULT_CHUNK_SIZE,
          "peak_buffer_bytes" => input.profile_peak_buffer_bytes,
          "source_bytes_read" => input.source_bytes.bytesize
        }
      end

      def runtime_observations(elapsed, allocations)
        {
          "elapsed_seconds" => observation(elapsed.round(6)),
          "allocated_objects" => observation(allocations)
        }
      end

      def observation(value)
        { "status" => "observation", "value" => value, "release_gate" => false }
      end

      def incremental_observation(parser_class, grammar, input, requested)
        return unavailable("not_requested", "workload has no committed incremental edit") unless requested
        if parser_feedback?(grammar)
          return unavailable(
            "not_measured",
            "syntax-only incremental parsing suppresses the parser action that changes lexer state"
          )
        end

        session = parser_class.syntax_session(input, execution_profile: :trusted_application_code)
        replacement = input.byteslice(0, 1) || ""
        edit = Runtime::CST::TextEdit.new(start: 0, delete_length: replacement.bytesize, insert_text: replacement)
        session.apply_edits([edit])
        runtime_parser = session.instance_variable_get(:@incremental).instance_variable_get(:@parser)
        scanned = runtime_parser.instance_variable_get(:@lexer_input).source_bytes.bytesize
        {
          "status" => "measured",
          "edited_source_bytes" => input.bytesize,
          "bytes_scanned_from_zero" => scanned,
          "share" => input.empty? ? 0.0 : scanned.fdiv(input.bytesize),
          "basis" => "scan_syntax_with_cache initializes the current generated lexer at byte zero"
        }
      rescue Runtime::ParseError => e
        unavailable("not_measured", "incremental fixture did not produce a complete syntax scan: #{e.class}")
      end

      def parser_feedback?(grammar)
        grammar.productions.any? { |production| state_mutation?(production.action&.code) }
      end

      def unavailable(status, reason)
        { "status" => status, "reason" => reason }
      end
    end
  end
end
