# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # Current parser-table shape emitted by the generator.
    PARSER_TABLE_FORMAT_VERSION = 5 #: Integer
    # Parser-table shapes this runtime can execute.
    SUPPORTED_PARSER_TABLE_FORMAT_VERSIONS = [1, 2, 3, 4, PARSER_TABLE_FORMAT_VERSION].freeze #: Array[Integer]
  end
end
