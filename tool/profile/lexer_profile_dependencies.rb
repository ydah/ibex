# frozen_string_literal: true

# Load only the parser-construction and generated-runtime graph exercised by
# H006. In particular, do not load the CLI or configuration graph through the
# public `ibex` aggregate while capturing evidence.
require_relative "../../lib/ibex/version"
require_relative "../../lib/ibex/frontend"
require_relative "../../lib/ibex/ir"
require_relative "../../lib/ibex/normalize"
require_relative "../../lib/ibex/analysis"
require_relative "../../lib/ibex/lalr"
require_relative "../../lib/ibex/codegen/ruby"

module Ibex
  module Profile
    # Repository source closure used to parse, normalize, construct, generate,
    # and execute the lexer-profile workloads.
    module LexerProfileDependencies
      ROOT = File.expand_path("../..", __dir__)
      SOURCE_PATTERNS = %w[
        lib/ibex/version.rb
        lib/ibex/error.rb
        lib/ibex/location.rb
        lib/ibex/configuration.rb
        lib/ibex/configuration/**/*.rb
        lib/ibex/generation_input.rb
        lib/ibex/tables.rb
        lib/ibex/analysis.rb
        lib/ibex/analysis/**/*.rb
        lib/ibex/frontend.rb
        lib/ibex/frontend/**/*.rb
        lib/ibex/ir.rb
        lib/ibex/ir/**/*.rb
        lib/ibex/normalize.rb
        lib/ibex/normalize/**/*.rb
        lib/ibex/lalr.rb
        lib/ibex/lalr/**/*.rb
        lib/ibex/runtime.rb
        lib/ibex/runtime/**/*.rb
        lib/ibex/tables/**/*.rb
        lib/ibex/codegen/action_locations.rb
        lib/ibex/codegen/action_method_source.rb
        lib/ibex/codegen/cst_metadata.rb
        lib/ibex/codegen/generated_action_abi.rb
        lib/ibex/codegen/ruby.rb
        lib/ibex/codegen/ruby_*.rb
      ].freeze
      source_paths = SOURCE_PATTERNS.flat_map do |pattern|
        Dir.glob(File.join(ROOT, pattern)).select { |path| File.file?(path) }
      end
      SOURCE_PATHS = source_paths.map { |path| path.delete_prefix("#{ROOT}/") }.uniq.sort.freeze

      module_function

      def verify_loaded!(root: ROOT)
        prefix = "#{File.expand_path(root)}/"
        loaded = $LOADED_FEATURES.filter_map do |path|
          expanded = File.expand_path(path)
          relative = expanded.delete_prefix(prefix)
          relative if expanded.start_with?(prefix) && relative.start_with?("lib/") && relative.end_with?(".rb")
        end.uniq.sort
        unbound = loaded - SOURCE_PATHS
        return if unbound.empty?

        raise "lexer profile loaded unbound repository sources: #{unbound.join(', ')}"
      end
    end
  end
end
