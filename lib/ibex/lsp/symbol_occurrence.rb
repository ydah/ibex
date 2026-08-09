# frozen_string_literal: true

module Ibex
  module LSP
    # @rbs!
    #   type symbol_key = [:symbol, String] | [:parameter, String, Integer, String] | [:include, String]
    #   type symbol_data_value = String | Symbol | Integer | bool | nil | Array[String] |
    #     Hash[Symbol, symbol_data_value]
    #   type symbol_data = Hash[Symbol, symbol_data_value]

    # A source-backed grammar symbol definition or reference.
    SymbolOccurrence = Struct.new(
      :name, #: String
      :kind, #: Symbol
      :role, #: Symbol
      :key, #: symbol_key
      :path, #: String
      :span, #: Frontend::SourceSpan
      :data, #: symbol_data
      keyword_init: true
    )
  end
end
