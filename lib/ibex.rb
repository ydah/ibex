# frozen_string_literal: true
# rbs_inline: enabled

require_relative "ibex/version"
require_relative "ibex/error"
require_relative "ibex/error_messages"
require_relative "ibex/artifact_set"
require_relative "ibex/generation_input"
require_relative "ibex/generation_manifest"
require_relative "ibex/generation_transaction"
require_relative "ibex/watch"
require_relative "ibex/tables"
require_relative "ibex/runtime"
require_relative "ibex/coverage"
require_relative "ibex/table_simulation"
require_relative "ibex/frontend"
require_relative "ibex/ir"
require_relative "ibex/normalize"
require_relative "ibex/analysis"
require_relative "ibex/samples"
require_relative "ibex/lalr"
require_relative "ibex/codegen/symbol_labels"
require_relative "ibex/codegen/report"
require_relative "ibex/codegen/explain"
require_relative "ibex/codegen/action_locations"
require_relative "ibex/codegen/action_method_source"
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
  ParseError = Runtime::ParseError #: singleton(Runtime::ParseError)
end
