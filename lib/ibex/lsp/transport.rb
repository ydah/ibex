# frozen_string_literal: true

module Ibex
  module LSP
    # Reads and writes bounded LSP JSON-RPC messages over Content-Length framing.
    class Transport
      HEADER_SEPARATOR = "\r\n\r\n"

      # @rbs (untyped input, untyped output) -> void
      def initialize(input, output)
        @input = input
        @output = output
        @buffer = String.new(encoding: Encoding::BINARY)
      end

      # @rbs () -> Hash[String, untyped]?
      def read_message
        header = read_header
        return unless header

        length = content_length(header)
        body = read_bytes(length)
        parsed = JSON.parse(body)
        raise ProtocolError.new("JSON-RPC message must be an object", code: -32_600) unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError => e
        raise ProtocolError.new("malformed JSON: #{e.message}", code: -32_700)
      end

      # @rbs (Hash[String, untyped] message) -> void
      def write_message(message)
        body = JSON.generate(message)
        if body.bytesize > Limits::MAX_OUTPUT_BYTES
          raise ProtocolError.new("JSON-RPC output exceeds #{Limits::MAX_OUTPUT_BYTES} bytes", code: -32_603)
        end

        @output.write("Content-Length: #{body.bytesize}\r\n\r\n")
        @output.write(body)
        @output.flush if @output.respond_to?(:flush)
      end

      private

      # @rbs () -> String?
      def read_header
        loop do
          index = @buffer.index(HEADER_SEPARATOR)
          if index
            if index > Limits::MAX_HEADER_BYTES
              raise ProtocolError.new("JSON-RPC header exceeds #{Limits::MAX_HEADER_BYTES} bytes",
                                      code: -32_700, fatal: true)
            end

            header = @buffer.byteslice(0, index) || ""
            @buffer = @buffer.byteslice(index + HEADER_SEPARATOR.bytesize, @buffer.bytesize) || +""
            return header
          end
          if @buffer.bytesize > Limits::MAX_HEADER_BYTES
            raise ProtocolError.new("JSON-RPC header exceeds #{Limits::MAX_HEADER_BYTES} bytes",
                                    code: -32_700, fatal: true)
          end

          chunk = read_chunk(4096)
          return nil if chunk.nil? && @buffer.empty?
          raise ProtocolError.new("truncated JSON-RPC header", code: -32_700, fatal: true) unless chunk

          @buffer << chunk.b
        end
      end

      # @rbs (String header) -> Integer
      def content_length(header)
        values = header.split("\r\n").filter_map do |line|
          name, value = line.split(":", 2)
          raise ProtocolError.new("malformed JSON-RPC header", code: -32_700, fatal: true) unless value

          value.strip if name&.casecmp?("Content-Length")
        end
        unless values.one? && values.fetch(0).match?(/\A\d+\z/)
          raise ProtocolError.new("exactly one numeric Content-Length header is required",
                                  code: -32_700, fatal: true)
        end

        length = Integer(values.fetch(0), 10)
        if length > Limits::MAX_MESSAGE_BYTES
          raise ProtocolError.new("JSON-RPC message exceeds #{Limits::MAX_MESSAGE_BYTES} bytes",
                                  code: -32_700, fatal: true)
        end
        length
      end

      # @rbs (Integer length) -> String
      def read_bytes(length)
        while @buffer.bytesize < length
          chunk = read_chunk([4096, length - @buffer.bytesize].min)
          raise ProtocolError.new("truncated JSON-RPC body", code: -32_700, fatal: true) unless chunk

          @buffer << chunk.b
        end
        body = @buffer.byteslice(0, length) || ""
        @buffer = @buffer.byteslice(length, @buffer.bytesize) || +""
        body.force_encoding(Encoding::UTF_8)
      end

      # IO#read(length) may wait for the entire length on a live pipe. readpartial
      # lets the stdio server process the bytes that are already available.
      # @rbs (Integer length) -> String?
      def read_chunk(length)
        return @input.read(length) unless @input.respond_to?(:readpartial)

        @input.readpartial(length)
      rescue EOFError
        nil
      end
    end
  end
end
