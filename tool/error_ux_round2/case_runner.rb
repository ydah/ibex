# frozen_string_literal: true

require "digest"
require "json"
require_relative "source_edit"

module Ibex
  module ErrorUXRound2
    # Observes diagnostics, bounded repair, and a fresh parse for one fixed case.
    class CaseRunner
      def initialize(definition, parser_class)
        @definition = definition
        @parser_class = parser_class
      end

      def build
        diagnostics = observe_diagnostics
        applied = SourceEdit.apply(
          @definition.fetch("input"), @definition.dig("proposed_edit", "operations"),
          case_id: @definition.fetch("id")
        )
        {
          "id" => @definition.fetch("id"),
          "dimensions" => @definition.fetch("dimensions"),
          "grammar" => @definition.fetch("grammar"),
          "input" => @definition.fetch("input"),
          "input_sha256" => sha256(@definition.fetch("input")),
          "observation" => diagnostics,
          "bounded_repair" => observe_repair,
          "proposed_edit" => @definition.fetch("proposed_edit").merge(
            "applied_source_sha256" => sha256(applied)
          ),
          "fresh_reparse" => fresh_reparse(applied, diagnostics),
          "semantic_value_risk" => @definition.fetch("semantic_value_risk"),
          "external_review" => { "status" => "pending", "labels" => [] }
        }
      end

      private

      def observe_diagnostics
        return observe_continuation if @definition.fetch("dimensions").include?("multi-error-continuation")

        parser = @parser_class.new
        parser.parse(@definition.fetch("input"))
        raise "#{@definition.fetch('id')}: invalid case was accepted"
      rescue Runtime::ParseError => e
        phase = lexer_failure?(e) ? "lexer" : "parser"
        {
          "mode" => "single-rejection",
          "parse_status" => phase == "lexer" ? "lexer-failure" : "rejected",
          "diagnostics" => [diagnostic(e, phase: phase)]
        }
      end

      def observe_continuation
        parser = @parser_class.new
        errors = []
        parser.define_singleton_method(:on_error) do |token_id, value, _stack|
          expected = expected_tokens
          token_name = token_to_str(token_id)
          location = instance_variable_get(:@lookahead_location)
          state = instance_variable_get(:@state_stack).last
          suggestions = send(:token_suggestions, token_name, expected)
          errors << Runtime::ParseError.new(
            token_id: token_id, token_name: token_name, token_value: value,
            expected_tokens: expected, location: location, state: state, suggestions: suggestions
          )
          nil
        end
        result = parser.parse(@definition.fetch("input"))
        unless errors.length >= 2
          raise "#{@definition.fetch('id')}: expected at least two synchronized diagnostics, got #{errors.length}"
        end

        offsets = errors.map { |error| location_value(error.location, :start_byte) }
        unless offsets.all?(Integer) && offsets.each_cons(2).all? { |left, right| left < right }
          raise "#{@definition.fetch('id')}: synchronized diagnostics must occur at distinct increasing offsets"
        end
        raise "#{@definition.fetch('id')}: synchronized continuation did not produce a result" if result.nil?

        {
          "mode" => "synchronized-continuation",
          "parse_status" => "accepted-after-recovery",
          "diagnostics" => errors.map { |error| diagnostic(error, phase: "parser") }
        }
      end

      def observe_repair
        return unavailable_repair if lexer_failure_observed?

        parser = @parser_class.new
        parser.repair_policy = Runtime::RepairPolicy.new
        plans = []
        parser.define_singleton_method(:on_repair) { |plan| plans << plan }
        parse_status = begin
          parser.parse(@definition.fetch("input"))
          "accepted"
        rescue Runtime::ParseError
          "rejected"
        end
        return { "status" => "not-found", "parse_status" => parse_status, "plan" => nil } if plans.empty?

        {
          "status" => "selected",
          "parse_status" => parse_status,
          "plan" => repair_plan(plans.first)
        }
      end

      def repair_plan(plan)
        document = JSON.parse(JSON.generate(plan.to_h))
        document.fetch("edits").each do |edit|
          token_id = edit.fetch("token_id")
          edit["token_id_scope"] = token_id.negative? ? "temporary-external" : "grammar"
          edit["token_id"] = nil if token_id.negative?
        end
        document
      end

      def unavailable_repair
        {
          "status" => "not-applicable", "parse_status" => "lexer-failure", "plan" => nil,
          "reason" => "lexer-failure-precedes-parser-repair"
        }
      end

      def fresh_reparse(source, original)
        value = @parser_class.new.parse(source)
        { "status" => "accepted", "diagnostic_count" => 0, "value_class" => value.class.name }
      rescue Runtime::ParseError => e
        current_byte = location_value(e.location, :start_byte)
        status = progress?(original, e, current_byte) ? "progress" : "rejected"
        {
          "status" => status,
          "diagnostic_count" => 1,
          "value_class" => nil,
          "diagnostic" => diagnostic(e, phase: lexer_failure?(e) ? "lexer" : "parser")
        }
      end

      def progress?(original, error, current_byte)
        original_diagnostic = original.fetch("diagnostics").first
        original_byte = original_diagnostic.dig("location", "start_byte")
        return false unless current_byte.is_a?(Integer) && original_byte.is_a?(Integer)

        operations = @definition.dig("proposed_edit", "operations")
        mapped_byte = SourceEdit.original_offset(current_byte, operations)
        return true if mapped_byte > original_byte
        return false unless mapped_byte == original_byte

        diagnostic_context_changed?(original_diagnostic, error)
      end

      def diagnostic_context_changed?(original, error)
        current_token = error.token_name || error.token_id.to_s
        original.fetch("token") != current_token &&
          original.fetch("state") != error.state &&
          original.dig("expected_tokens", "tokens") != error.expected_tokens
      end

      def diagnostic(error, phase:)
        location = error.location
        source_line = location_value(location, :source_line) || @definition.fetch("input").lines.first.to_s.chomp
        column = location_value(location, :column) || 1
        expected = if phase == "lexer"
                     {
                       "availability" => "not-available",
                       "tokens" => [],
                       "reason" => "lexer-failure-precedes-parser-state"
                     }
                   else
                     { "availability" => "available", "tokens" => error.expected_tokens, "reason" => nil }
                   end
        {
          "phase" => phase,
          "message" => error.message,
          "token" => error.token_name || error.token_id.to_s,
          "expected_tokens" => expected,
          "state" => error.state,
          "location" => {
            "line" => location_value(location, :line) || 1,
            "column" => column,
            "start_byte" => location_value(location, :start_byte),
            "source_line" => source_line,
            "caret" => "#{' ' * [column - 1, 0].max}^"
          }
        }
      end

      def lexer_failure_observed?
        @definition.fetch("dimensions").include?("lexer-failure")
      end

      def lexer_failure?(error)
        error.token_name == "lexer input" && error.state.nil?
      end

      def location_value(location, key)
        return unless location
        return location.public_send(key) if location.respond_to?(key)
        return location[key] || location[key.to_s] if location.is_a?(Hash)

        nil
      end

      def sha256(value)
        Digest::SHA256.hexdigest(value.b)
      end
    end
  end
end
