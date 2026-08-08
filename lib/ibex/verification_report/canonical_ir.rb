# frozen_string_literal: true
# rbs_inline: enabled

require "digest"
require "json"

module Ibex
  module VerificationReport
    # Rebuilds immutable IR with source locations expressed as report logical identities.
    class CanonicalIR
      LOGICAL_ROOT = "input" #: String

      # @rbs (IR::Automaton automaton, source_records: Array[GenerationInput]) -> void
      def initialize(automaton, source_records:)
        raise ArgumentError, "source_records must not be empty" if source_records.empty?
        if source_records.length > LogicalPath::MAX_INPUT_FILES
          raise ArgumentError, "verification reports support at most #{LogicalPath::MAX_INPUT_FILES} input files"
        end

        @automaton = automaton
        @logical_files = source_records.map.with_index do |record, index|
          [record, LogicalPath.input(record.path, index)]
        end
      end

      # @rbs () -> IR::Automaton
      def build
        document = JSON.parse(IR::Serialize.dump(@automaton))
        normalize_source_identity!(document)
        grammar = IR::Validator.validate(generate_json(document.fetch("grammar")))
        raise ArgumentError, "canonical bundle grammar did not validate" unless grammar.is_a?(IR::Grammar)

        document["grammar_digest"] = digest(grammar)
        automaton = IR::Validator.validate(generate_json(document))
        raise ArgumentError, "canonical bundle automaton did not validate" unless automaton.is_a?(IR::Automaton)

        automaton
      end

      private

      # @rbs (untyped value) -> untyped
      def normalize_source_identity!(value)
        case value
        when Array then value.each { |child| normalize_source_identity!(child) }
        when Hash
          value.each do |key, child|
            value[key] = if key == "file" && child.is_a?(String)
                           logical_file(child)
                         elsif key == "root" && child.is_a?(String)
                           LOGICAL_ROOT
                         else
                           normalize_source_identity!(child)
                         end
          end
        end
        value
      end

      # @rbs (untyped value) -> String
      def generate_json(value)
        JSON.generate(normalize_for_json(value))
      end

      # @rbs (untyped value) -> untyped
      def normalize_for_json(value)
        case value
        when String
          normalized = value.dup.force_encoding(Encoding::UTF_8)
          normalized.valid_encoding? ? normalized : value
        when Array
          value.map { |child| normalize_for_json(child) }
        when Hash
          value.each_with_object({}) do |(key, child), normalized|
            normalized[normalize_for_json(key)] = normalize_for_json(child)
          end
        else
          value
        end
      end

      # @rbs (String file) -> String
      def logical_file(file)
        logical = @logical_files.find { |_record, path| path == file }
        return logical.fetch(1) if logical

        candidates = @logical_files.select { |record, _path| record_matches?(record, file) }
        return candidates.fetch(0).fetch(1) if candidates.one?

        detail = candidates.empty? ? "is not present in source_records" : "matches multiple source_records"
        raise ArgumentError, "IR source location #{file.inspect} #{detail}"
      end

      # @rbs (GenerationInput record, String file) -> bool
      def record_matches?(record, file)
        paths = [record.path, *record.access_paths]
        return true if paths.include?(file)
        return true if absolute_file?(file) && paths.include?(File.expand_path(file))

        !absolute_file?(file) && paths.any? do |path|
          path == file || path.end_with?("/#{file}")
        end
      end

      # @rbs (String file) -> bool
      def absolute_file?(file)
        file.start_with?("/") || file.match?(%r{\A[A-Za-z]:[\\/]})
      end

      # @rbs (IR::Grammar grammar) -> String
      def digest(grammar)
        "sha256:#{Digest::SHA256.hexdigest(IR::Serialize.dump(grammar))}"
      end
    end
  end
end
