# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Codegen
    # Emits declarative value-printer tables and methods for Ruby parsers.
    module RubyValuePrinters
      # @rbs @grammar: IR::Grammar
      # @rbs @line_convert: bool
      # @rbs @value_printer_action_method_source: ActionMethodSource?

      private

      # @rbs (Array[String] lines, String indent) -> void
      def append_value_printer_table(lines, indent)
        return if @grammar.value_printers.empty?

        entries = @grammar.value_printers.map do |printer|
          symbol = @grammar.symbol(printer[:symbol]) ||
                   raise(Ibex::Error, "missing printer symbol #{printer[:symbol]}")
          "#{symbol.id} => :_ibex_value_printer_#{symbol.id}"
        end
        lines << "#{indent}VALUE_PRINTERS = { #{entries.join(', ')} }.freeze"
      end

      # @rbs (Array[String] lines) -> void
      def append_value_printers(lines)
        @grammar.value_printers.each do |printer|
          append_value_printer(lines, printer)
          lines << ""
        end
      end

      # @rbs (Array[String] lines, IR::value_printer printer) -> void
      def append_value_printer(lines, printer)
        symbol = @grammar.symbol(printer[:symbol]) ||
                 raise(Ibex::Error, "missing printer symbol #{printer[:symbol]}")
        source_builder = value_printer_action_method_source
        source = source_builder.value_printer_method_source(symbol.id, printer)
        if @line_convert
          location = printer[:loc]
          lines << "  class_eval(#{source.dump}, #{location[:file].inspect}, #{location[:line]})"
        elsif source_builder.column_sensitive?(printer[:code])
          lines << source
        else
          source.lines.each { |line| lines << "  #{line.rstrip}" }
        end
      end

      # @rbs () -> ActionMethodSource
      def value_printer_action_method_source
        @value_printer_action_method_source ||= ActionMethodSource.new(@grammar)
      end
    end
  end
end
