# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require "optparse"

module Ibex
  module Impact
    # Stores only conflict identities so a baseline is stable across state ids.
    class Baseline
      # @rbs (String path) -> void
      def initialize(path)
        @path = path
      end

      # @rbs () -> Array[String]
      def conflicts
        return [] unless File.file?(@path)

        value = JSON.parse(File.binread(@path))
        empty_conflicts = [] #: Array[untyped]
        conflicts = value.fetch("conflicts", empty_conflicts) #: Array[untyped]
        raise Ibex::Error, "#{@path}:1:1: baseline conflicts must be an array" unless conflicts.is_a?(Array)

        conflicts.map(&:to_s).sort.uniq
      rescue JSON::ParserError, KeyError => e
        raise Ibex::Error, "#{@path}:1:1: invalid impact baseline: #{e.message}"
      end

      # @rbs (Array[String] identities) -> void
      def write(identities)
        File.write(@path, "#{JSON.pretty_generate({ 'schema_version' => 1, 'conflicts' => identities.sort.uniq })}\n")
      end
    end

    # Severity ranking and CI gate evaluation for impact findings.
    module Severity
      LEVELS = %w[info low medium high critical].freeze #: Array[String]
      FAIL_ON = %w[
        new_conflict nullable_change first_change follow_change action_arity unreachable
      ].freeze #: Array[String]
      RANK = LEVELS.each_with_index.to_h.freeze #: Hash[String, Integer]
      GATE_TO_KIND = {
        "nullable_change" => "nullable", "first_change" => "first", "follow_change" => "follow"
      }.freeze #: Hash[String, String]

      module_function

      # @rbs (String left, String right) -> String
      def max(left, right)
        RANK.fetch(left) >= RANK.fetch(right) ? left : right
      end

      # @rbs (Hash[String, Array[String]], Array[Hash[Symbol, String]]) -> Hash[String, String]
      def symbols(changes, actions)
        levels = Hash.new("info") #: Hash[String, String]
        changes.each do |name, kinds|
          kinds.each do |kind|
            level = level_for_kind(kind)
            levels[name] = max(levels[name], level)
          end
        end
        actions.each do |finding|
          name = finding.fetch(:production).split(" -> ").first
          levels[name] = max(levels[name], finding.fetch(:severity))
        end
        levels
      end

      # @rbs (String) -> String
      def level_for_kind(kind)
        return "high" if %w[first follow nullable].include?(kind)
        return "medium" if kind == "reference"

        "low"
      end

      # @rbs (Hash[Symbol, Object?] report, Array[String] gates) -> bool
      def fails?(report, gates)
        return false if gates.empty?

        return true if conflict_gate?(report, gates)
        return true if unreachable_gate?(report, gates)
        return true if action_gate?(report, gates)

        symbol_records = report.fetch(:symbols, []) #: Array[Hash[Symbol, Object?]]
        gates.any? do |gate|
          kind = GATE_TO_KIND[gate]
          kind && symbol_records.any? { |item| item[:kinds].is_a?(Array) && item[:kinds].include?(kind) }
        end
      end

      # @rbs (Hash[Symbol, Object?], Array[String]) -> bool
      def conflict_gate?(report, gates)
        gates.include?("new_conflict") && report.dig(:automaton, :conflicts, :added)&.any?
      end

      # @rbs (Hash[Symbol, Object?], Array[String]) -> bool
      def unreachable_gate?(report, gates)
        gates.include?("unreachable") && report.dig(:automaton, :unreachable)&.any?
      end

      # @rbs (Hash[Symbol, Object?], Array[String]) -> bool
      def action_gate?(report, gates)
        return false unless gates.include?("action_arity")

        action_records = report.fetch(:actions, []) #: Array[Hash[Symbol, Object?]]
        action_records.any? { |item| item[:severity] == "high" }
      end

      # @rbs (Array[String] gates) -> Array[String]
      def validate_gates(gates)
        unknown = gates - FAIL_ON
        raise OptionParser::InvalidArgument, "unknown --fail-on value #{unknown.first.inspect}" unless unknown.empty?

        gates.uniq
      end
    end
  end
end
