# frozen_string_literal: true
# rbs_inline: enabled

require_relative "ibex/version"
require_relative "ibex/error"
require_relative "ibex/configuration"
require_relative "ibex/messages"
require_relative "ibex/location"
require_relative "ibex/error_messages"
require_relative "ibex/artifact_set"
require_relative "ibex/generation_input"
require_relative "ibex/generation_manifest"
require_relative "ibex/generation_transaction"
require_relative "ibex/watch"
require_relative "ibex/tables"
require "ibex/runtime"
require_relative "ibex/frontend"
require_relative "ibex/ir"
require_relative "ibex/normalize"
require_relative "ibex/analysis"
require_relative "ibex/lalr"
require_relative "ibex/codegen/symbol_labels"
require_relative "ibex/codegen/report"
require_relative "ibex/codegen/explain"
require_relative "ibex/codegen/ambiguity"
require_relative "ibex/codegen/action_locations"
require_relative "ibex/codegen/generated_action_abi"
require_relative "ibex/codegen/action_method_source"
require_relative "ibex/codegen/cst_metadata"
require_relative "ibex/codegen/ruby_actions"
require_relative "ibex/codegen/ruby"
require_relative "ibex/codegen/rbs"
require_relative "ibex/codegen/action_source"
require_relative "ibex/codegen/dot"
require_relative "ibex/codegen/mermaid"
require_relative "ibex/codegen/html"
require_relative "ibex/codegen/railroad"
require_relative "ibex/codegen/documentation"

# Ibex generates and runs Pure Ruby LR parsers.
module Ibex
  # Steep models __dir__ as nilable although Ruby defines it for loaded files.
  # steep:ignore:start
  autoload :Coverage, File.join(__dir__, "ibex/coverage")
  autoload :TableSimulation, File.join(__dir__, "ibex/table_simulation")
  autoload :Samples, File.join(__dir__, "ibex/samples")
  autoload :Fuzz, File.join(__dir__, "ibex/fuzz")
  autoload :DeltaReducer, File.join(__dir__, "ibex/delta_reducer")
  autoload :Verify, File.join(__dir__, "ibex/verify")
  autoload :Equiv, File.join(__dir__, "ibex/equiv")
  autoload :Diff, File.join(__dir__, "ibex/diff")
  autoload :Metrics, File.join(__dir__, "ibex/metrics")
  autoload :Impact, File.join(__dir__, "ibex/impact")
  autoload :Fix, File.join(__dir__, "ibex/fix")
  autoload :BisonImport, File.join(__dir__, "ibex/bison_import")
  autoload :GrammarTests, File.join(__dir__, "ibex/grammar_tests")
  autoload :RaccMigration, File.join(__dir__, "ibex/racc_migration")
  # steep:ignore:end

  ParseError = Runtime::ParseError #: singleton(Runtime::ParseError)
  ResourceLimitError = Runtime::ResourceLimitError #: singleton(Runtime::ResourceLimitError)
end
