# frozen_string_literal: true

require "json"
require "uri"
require_relative "version"
require_relative "error"
require_relative "frontend"
require_relative "lsp/protocol_error"
require_relative "lsp/transport"
require_relative "lsp/position_codec"
require_relative "lsp/workspace"
require_relative "lsp/workspace_analyzer"
require_relative "lsp/document_store_validation"
require_relative "lsp/document_store_diagnostics"
require_relative "lsp/document_store"
require_relative "lsp/symbol_occurrence"
require_relative "lsp/symbol_index_source_queries"
require_relative "lsp/symbol_index_precedence_references"
require_relative "lsp/symbol_index_builder"
require_relative "lsp/symbol_index"
require_relative "lsp/request_support"
require_relative "lsp/initialization_handlers"
require_relative "lsp/document_handlers"
require_relative "lsp/navigation_handlers"
require_relative "lsp/request_handlers"
require_relative "lsp/server"

module Ibex
  # Language Server Protocol support for grammar workspaces.
  module LSP
  end
end
