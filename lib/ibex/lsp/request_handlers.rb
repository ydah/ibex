# frozen_string_literal: true

module Ibex
  module LSP
    # Dispatches the finite LSP surface to focused lifecycle, document, and navigation handlers.
    module RequestHandlers
      include InitializationHandlers
      include DocumentHandlers
      include NavigationHandlers
      include RequestSupport

      HANDLERS = {
        "initialize" => :initialize_workspace,
        "initialized" => :initialized_notification,
        "shutdown" => :shutdown_request,
        "exit" => :exit_notification,
        "textDocument/didOpen" => :did_open,
        "textDocument/didChange" => :did_change,
        "textDocument/didSave" => :did_save,
        "textDocument/didClose" => :did_close,
        "textDocument/definition" => :definition,
        "textDocument/references" => :references,
        "textDocument/prepareRename" => :prepare_rename,
        "textDocument/rename" => :rename,
        "textDocument/hover" => :hover,
        "textDocument/completion" => :completion,
        "$/cancelRequest" => :cancel_request
      }.freeze #: Hash[String, Symbol]

      private

      # @rbs (String method, lsp_value? params) -> lsp_value?
      def dispatch(method, params)
        handler = HANDLERS[method]
        raise ProtocolError.new("method not found: #{method}", code: -32_601) unless handler

        send(handler, params)
      end

      # @rbs (lsp_value? params) -> nil
      def cancel_request(_params)
        nil
      end
    end
  end
end
