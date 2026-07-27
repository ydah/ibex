# frozen_string_literal: true

# Internal frontend surface needed by the ordinary grammar-to-Ruby pipeline.
# Public `require "ibex/frontend"` continues to load formatting, diagnostics,
# the DSL, and every other frontend facility.
require_relative "../error"
require_relative "../tables"
require_relative "../runtime/parser"
require_relative "source_span"
require_relative "source_cursor"
require_relative "source_document"
require_relative "diagnostic"
require_relative "action_scanner"
require_relative "lexer"
require_relative "lexer_recovery"
require_relative "ast"
require_relative "rule_documentation"
require_relative "token_adapter/declaration_document_state"
require_relative "token_adapter/declaration_state"
require_relative "token_adapter/delimiter_tracker"
require_relative "token_adapter/rule_state"
require_relative "token_adapter"
require_relative "generated_parser_base"
require_relative "generated_parser"
require_relative "parser"
require_relative "resolution"
require_relative "source_loader"
require_relative "resolver"

module Ibex
  module Frontend
  end
end
