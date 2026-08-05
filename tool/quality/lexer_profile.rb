# frozen_string_literal: true

require "json"
require "json_schemer"
require_relative "../profile/lexer_profile_report"
require_relative "lexer_profile_integrity"

module Ibex
  module Quality
    # Validates H006 evidence, provenance, semantics, and deterministic observations.
    class LexerProfile
      def initialize(root: File.expand_path("../..", __dir__), evidence: nil, output: $stdout)
        @root = File.expand_path(root)
        @evidence = evidence || File.join(@root, "tool/profile/evidence/lexer-profile-v1.json")
        @output = output
      end

      def verify!
        document = JSON.parse(File.binread(@evidence))
        validate!(document, committed: true)
        current = Profile::LexerProfileReport.new(root: @root).build
        validate!(current, committed: false)
        unless deterministic_projection(document) == deterministic_projection(current)
          raise "lexer profile deterministic evidence drift; regenerate with tool/lexer_profile.rb"
        end

        @output.puts "lexer profile evidence matches deterministic semantic observations"
        document
      end

      private

      def validate!(document, committed:)
        validate_schema!(document)
        LexerProfileProvenance.new(root: @root, document: document).verify!(committed: committed)
        LexerProfileSemantics.new(document).verify!
      end

      def validate_schema!(document)
        path = File.join(@root, "schema/lexer-profile-v1.schema.json")
        errors = JSONSchemer.schema(JSON.parse(File.binread(path))).validate(document).to_a
        raise "lexer profile evidence violates schema: #{JSON.generate(errors)}" unless errors.empty?
      end

      def deterministic_projection(document)
        Profile::LexerProfileDigest.deterministic_report_input(document)
      end
    end
  end
end
