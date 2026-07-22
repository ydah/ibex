# frozen_string_literal: true
# rbs_inline: enabled

require_relative "ibex/version"
require_relative "ibex/error"
require_relative "ibex/tables"
require_relative "ibex/runtime"
require_relative "ibex/frontend"
require_relative "ibex/ir"
require_relative "ibex/normalize"
require_relative "ibex/analysis"
require_relative "ibex/lalr"
require_relative "ibex/codegen/report"
require_relative "ibex/codegen/ruby"
require_relative "ibex/codegen/rbs"
require_relative "ibex/codegen/dot"
require_relative "ibex/codegen/html"

# Ibex generates and runs Pure Ruby LR parsers.
module Ibex
  ParseError = Runtime::ParseError #: singleton(Runtime::ParseError)
end
