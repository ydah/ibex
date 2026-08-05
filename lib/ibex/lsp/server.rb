# frozen_string_literal: true

module Ibex
  module LSP
    # Coordinates JSON-RPC lifecycle, request responses, and protocol-safe logging.
    class Server
      include RequestHandlers

      REQUEST_METHODS = %w[
        initialize shutdown textDocument/definition textDocument/references textDocument/prepareRename
        textDocument/rename textDocument/hover textDocument/completion
      ].freeze #: Array[String]
      NOTIFICATION_METHODS = %w[
        initialized exit textDocument/didOpen textDocument/didChange textDocument/didSave textDocument/didClose
        $/cancelRequest
      ].freeze #: Array[String]

      # @rbs (stdin: untyped, stdout: untyped, stderr: untyped) -> void
      def initialize(stdin:, stdout:, stderr:)
        @transport = Transport.new(stdin, stdout)
        @stderr = stderr
        @state = :uninitialized
        @exit_requested = false
        @exit_status = nil #: Integer?
      end

      # @rbs () -> Integer
      def run
        until @exit_requested
          message = read_message
          break unless message

          process_message(message)
        end
        @exit_status || 1
      end

      private

      # @rbs () -> Hash[String, untyped]?
      def read_message
        @transport.read_message
      rescue ProtocolError => e
        send_error(nil, e)
        @exit_requested = true if e.fatal
        retry unless e.fatal
        nil
      end

      # @rbs (Hash[String, untyped] message) -> void
      def process_message(message)
        request_id = safe_request_id(message)
        notification = notification_envelope?(message)
        request_id = validate_envelope(message)
        method = message.fetch("method")
        validate_message_kind!(method, message.key?("id"))
        return if request_id.nil? && method.start_with?("$/")

        validate_lifecycle!(method)
        result = dispatch(method, message["params"])
        send_result(request_id, result) if request_id
      rescue ProtocolError => e
        notification ? log(e.message) : send_error(request_id, e)
      rescue StandardError => e
        error = ProtocolError.new("internal error: #{e.message}", code: -32_603)
        notification ? log(error.message) : send_error(request_id, error)
      end

      # @rbs (Hash[String, untyped] message) -> (String | Integer)?
      def safe_request_id(message)
        value = message["id"]
        value if valid_request_id?(value)
      end

      # @rbs (Hash[String, untyped] message) -> bool
      def notification_envelope?(message)
        !message.key?("id") && message["jsonrpc"] == "2.0" && message["method"].is_a?(String)
      end

      # @rbs (String method, bool request) -> void
      def validate_message_kind!(method, request)
        if REQUEST_METHODS.include?(method) && !request
          raise ProtocolError.new("#{method} must be a request", code: -32_600)
        end
        return unless NOTIFICATION_METHODS.include?(method) && request

        raise ProtocolError.new("#{method} must be a notification", code: -32_600)
      end

      # @rbs (Hash[String, untyped] message) -> (String | Integer)?
      def validate_envelope(message)
        unless message["jsonrpc"] == "2.0" && message["method"].is_a?(String)
          raise ProtocolError.new("invalid JSON-RPC request", code: -32_600)
        end
        return nil unless message.key?("id")

        request_id = message["id"]
        unless valid_request_id?(request_id)
          raise ProtocolError.new("request id must be a bounded string or integer", code: -32_600)
        end

        request_id
      end

      # @rbs (untyped value) -> bool
      def valid_request_id?(value)
        return false unless value.is_a?(String) || value.is_a?(Integer)

        value.to_s.bytesize <= Limits::MAX_REQUEST_ID_BYTES
      end

      # @rbs (String method) -> void
      def validate_lifecycle!(method)
        return if method == "exit"
        return if @state == :uninitialized && method == "initialize"
        return if @state == :initialized && %w[initialized shutdown].include?(method)
        return if @state == :running

        code = @state == :uninitialized ? -32_002 : -32_600
        raise ProtocolError.new("request is invalid in #{@state} server state", code: code)
      end

      # @rbs (String | Integer request_id, untyped result) -> void
      def send_result(request_id, result)
        @transport.write_message("jsonrpc" => "2.0", "id" => request_id, "result" => result)
      rescue ProtocolError => e
        send_error(request_id, e)
      end

      # @rbs (String | Integer | nil request_id, ProtocolError error) -> void
      def send_error(request_id, error)
        @transport.write_message(
          "jsonrpc" => "2.0", "id" => request_id,
          "error" => { "code" => error.code, "message" => error.message }
        )
      rescue ProtocolError => e
        log(e.message)
      end

      # @rbs (String message) -> void
      def log(message)
        @stderr.puts(message)
      end
    end
  end
end
