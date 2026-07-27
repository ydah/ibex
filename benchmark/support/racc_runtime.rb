# frozen_string_literal: true

module BenchmarkSupport
  # Selects and verifies the Racc runtime used by an isolated benchmark worker.
  module RaccRuntime
    BACKENDS = %w[native ruby].freeze

    module_function

    def load!(backend)
      raise ArgumentError, "unknown Racc backend #{backend.inspect}" unless BACKENDS.include?(backend)

      select_ruby_backend! if backend == "ruby" && !parser_loaded?
      require "racc/parser"
      actual = current_backend
      return actual if actual == backend

      raise "Racc runtime backend must be #{backend.inspect}; loaded #{actual.inspect}"
    end

    def current_backend
      raise "Racc runtime is not loaded" unless parser_loaded?

      Racc::Parser.racc_runtime_type == "ruby" ? "ruby" : "native"
    end

    def parser_loaded?
      Object.const_defined?(:Racc, false) &&
        Racc.const_defined?(:Parser, false) &&
        Racc::Parser.respond_to?(:racc_runtime_type)
    end
    private_class_method :parser_loaded?

    def select_ruby_backend!
      Object.const_set(:Racc, Module.new) unless Object.const_defined?(:Racc, false)
      if Racc.const_defined?(:Racc_No_Extensions, false)
        return if Racc.const_get(:Racc_No_Extensions, false)

        raise "Racc_No_Extensions was already disabled before selecting the Ruby backend"
      end

      Racc.const_set(:Racc_No_Extensions, true)
    end
    private_class_method :select_ruby_backend!
  end
end
