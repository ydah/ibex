# frozen_string_literal: true

require_relative "ibex/version"
require_relative "ibex/runtime"

# Ibex generates and runs Pure Ruby LR parsers.
module Ibex
  class Error < StandardError; end

  ParseError = Runtime::ParseError
end
