# frozen_string_literal: true

module Ibex
  module Quality
    # Enforces the closed compatibility table for an ABI assessment choice.
    module RuntimeABIAssessmentChoice
      def self.verify!(state:, choice:, regeneration:, surfaces:)
        if state == "not_applicable" || choice == "none"
          raise "runtime-facing changes cannot use not_applicable or none"
        end
        raise "runtime-facing changes must declare concrete surfaces" if surfaces.include?("none")

        case choice
        when "current_contract" then current_contract!(state, regeneration)
        when "sidecar" then sidecar!(state, regeneration, surfaces)
        when "new_table_format" then new_table_format!(state, regeneration, surfaces)
        when "new_ir_version" then new_ir_version!(state, regeneration, surfaces)
        when "new_runtime_major" then new_runtime_major!(state, regeneration, surfaces)
        end
      end

      def self.current_contract!(state, regeneration)
        raise "current_contract requires compatible state" unless state == "compatible"
        raise "current_contract must decide regeneration" if regeneration == "not_applicable"
      end
      private_class_method :current_contract!

      def self.sidecar!(state, regeneration, surfaces)
        return if state == "compatible" && regeneration == "not_required" && surfaces == ["generation_metadata"]

        raise "sidecar requires compatible generation_metadata with no regeneration"
      end
      private_class_method :sidecar!

      def self.new_table_format!(state, regeneration, surfaces)
        return if state == "breaking" && regeneration == "required" && surfaces.include?("parser_table")

        raise "new_table_format requires breaking parser_table and regeneration"
      end
      private_class_method :new_table_format!

      def self.new_ir_version!(state, regeneration, surfaces)
        ir_surfaces = %w[grammar_ir automaton_ir lexer_ir]
        return if state == "breaking" && regeneration != "not_applicable" && (surfaces & ir_surfaces).any?

        raise "new_ir_version requires breaking state, a matching IR surface, and a regeneration decision"
      end
      private_class_method :new_ir_version!

      def self.new_runtime_major!(state, regeneration, surfaces)
        runtime_surfaces = %w[runtime_api embedded_runtime]
        return if state == "breaking" && regeneration != "not_applicable" && (surfaces & runtime_surfaces).any?

        raise "new_runtime_major requires breaking runtime surface and a regeneration decision"
      end
      private_class_method :new_runtime_major!
    end
  end
end
