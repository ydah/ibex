# frozen_string_literal: true

require_relative "../../lib/ibex"

module Ibex
  module Quality
    # Runs independent verification over the self-authored grammar gallery.
    class Verify
      ALGORITHMS = %i[slr lalr ielr lr1].freeze
      TABLE_FORMATS = %i[plain compact].freeze

      def initialize(root: File.expand_path("../..", __dir__), output: $stdout)
        @root = root
        @output = output
      end

      def run(strict: false)
        checks = 0
        grammar_paths.each do |path|
          grammar = normalize(path)
          ALGORITHMS.each do |algorithm|
            automaton = LALR::Builder.new(grammar, algorithm: algorithm).build
            TABLE_FORMATS.each do |format|
              Tables.build(automaton, format: format)
              result = Ibex::Verify::Verifier.new(automaton, strict: strict).verify
              unless result.valid?
                raise Ibex::Error,
                      "#{relative(path)} #{algorithm}/#{format}: #{result.violations.map(&:to_h).inspect}"
              end
              checks += 1
            end
          end
        end
        @output.puts "verify#{':strict' if strict}: #{checks} gallery/algorithm/table combinations"
        checks
      end

      private

      def grammar_paths
        Dir.glob(File.join(@root, "gallery/*/grammar.y"))
      end

      def normalize(path)
        source = File.binread(path)
        ast = Frontend::Parser.new(source, file: relative(path), mode: :extended).parse
        Normalizer.new(ast, mode: :extended).normalize
      end

      def relative(path)
        path.delete_prefix("#{@root}/")
      end
    end
  end
end
