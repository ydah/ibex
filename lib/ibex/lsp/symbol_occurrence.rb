# frozen_string_literal: true

module Ibex
  module LSP
    # A source-backed grammar symbol definition or reference.
    SymbolOccurrence = Struct.new(
      :name, #: String
      :kind, #: Symbol
      :role, #: Symbol
      :key, #: Array[untyped]
      :path, #: String
      :span, #: Frontend::SourceSpan
      :data, #: Hash[Symbol, untyped]
      keyword_init: true
    )
  end
end
