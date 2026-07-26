# frozen_string_literal: true

module BenchmarkSupport
  # Loads only the public application dependencies needed by one parser workload.
  class PublicWorkloadDriver
    def initialize(identifier, checkout, generated_output, implementation)
      @identifier = identifier
      @checkout = checkout
      @generated_output = generated_output
      @implementation = implementation
    end

    def load!
      $LOAD_PATH.unshift(lib_directory) unless $LOAD_PATH.include?(lib_directory)
      load_runtime
      send(:"load_#{@identifier}")
      self
    end

    def parser
      send(:"build_#{@identifier}")
    end

    def parse(parser, input)
      canonicalize(@identifier, parser.parse(input))
    end

    private

    def load_runtime
      if @implementation == "ibex"
        require "ibex/runtime"
        install_migration_adapter unless @identifier == "namae"
      else
        require "racc/parser"
      end
    end

    def install_migration_adapter
      Object.const_set(:Racc, Module.new) unless Object.const_defined?(:Racc, false)
      Racc.const_set(:Parser, Ibex::Runtime::Parser) unless Racc.const_defined?(:Parser, false)
    end

    def load_namae
      Object.const_set(:Namae, Module.new) unless Object.const_defined?(:Namae, false)
      require "namae/name"
      load @generated_output
    end

    def build_namae
      Namae::Parser.new
    end

    def load_bcdice_command
      require "bcdice/enum"
      load @generated_output
    end

    def build_bcdice_command
      BCDice::Command::Parser.new("LL", round_type: BCDice::RoundType::FLOOR)
                             .enable_prefix_number
                             .enable_suffix_number
                             .enable_critical
                             .enable_fumble
                             .enable_dollar
                             .enable_question_target
    end

    def load_nokogiri_css
      require "nokogiri/syntax_error"
      require "nokogiri/css/syntax_error"
      require "nokogiri/css/node"
      require "nokogiri/css/tokenizer"
      load @generated_output
    end

    def build_nokogiri_css
      Nokogiri::CSS::Parser.new
    end

    def canonicalize(identifier, result)
      case identifier
      when "namae"
        result.map { |name| name.each_pair.to_h.transform_keys(&:to_s) }
      when "bcdice_command"
        canonical_bcdice_result(result)
      when "nokogiri_css"
        result.map(&:to_a)
      else
        raise ArgumentError, "unknown public workload driver #{identifier.inspect}"
      end
    end

    def canonical_bcdice_result(result)
      return nil unless result

      %i[
        command prefix_number suffix_number critical fumble dollar modify_number
        cmp_op target_number question_target?
      ].to_h { |method| [method.to_s, result.public_send(method)] }
    end

    def lib_directory
      File.join(@checkout, "lib")
    end
  end
end
