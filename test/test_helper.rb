# frozen_string_literal: true

if ENV["IBEX_MUTATION"] == "1"
  require "minitest"
  require "minitest/mock"
  require "mutant/minitest/coverage"
else
  require "minitest/autorun"
  require "minitest/mock"
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ibex"
require "ibex/cli"
