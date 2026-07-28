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
require "uri"

module TestURI
  PARSER = begin
    URI::RFC2396_PARSER
  rescue NameError
    URI::DEFAULT_PARSER
  end
end

module TestRuntimeCapabilities
  class << self
    def allocation_counter?
      before = total_allocated_objects
      return false unless before

      sample = Array.new(128) { Object.new }
      after = total_allocated_objects
      sample.clear
      !after.nil? && after > before
    end

    def make_shareable(value)
      capability = ractor
      return value unless capability.respond_to?(:make_shareable)

      capability.make_shareable(value)
    end

    def ractor_shareable?(value)
      capability = ractor
      capability.shareable?(value) if capability.respond_to?(:shareable?)
    end

    private

    def ractor
      Object.const_get(:Ractor, false) if Object.const_defined?(:Ractor, false)
    end

    def total_allocated_objects
      value = GC.stat[:total_allocated_objects]
      value if value.is_a?(Integer)
    end
  end
end
