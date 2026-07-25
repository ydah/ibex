# frozen_string_literal: true

module Ibex
  module LSP
    # Resource bounds shared by transport and open-document validation.
    module Limits
      MAX_HEADER_BYTES = 16 * 1024
      MAX_MESSAGE_BYTES = 1024 * 1024
      MAX_DOCUMENT_BYTES = 2 * 1024 * 1024
      MAX_OUTPUT_BYTES = 1024 * 1024
      MAX_ERROR_MESSAGE_CHARACTERS = 1024
      MAX_REQUEST_ID_BYTES = 256
    end

    # Bounded protocol and workspace failures with their JSON-RPC error code.
    class ProtocolError < Ibex::Error
      attr_reader :code #: Integer
      attr_reader :request_id #: String | Integer | nil
      attr_reader :fatal #: bool

      # @rbs (String message, ?code: Integer, ?request_id: String | Integer | nil, ?fatal: bool) -> void
      def initialize(message, code: -32_600, request_id: nil, fatal: false)
        normalized = message.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        bounded = normalized[0, Limits::MAX_ERROR_MESSAGE_CHARACTERS] || ""
        bounded += "…" if bounded.length < normalized.length
        super("(lsp):1:1: #{bounded}")
        @code = code
        @request_id = request_id
        @fatal = fatal
      end
    end
  end
end
