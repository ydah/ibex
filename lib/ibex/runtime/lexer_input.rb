# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # Incremental String, IO, or Fiber input used by generated lexers.
    class LexerInput
      DEFAULT_CHUNK_SIZE = 16 * 1024 #: Integer

      attr_reader :buffer #: String

      # @rbs (String | IO | Fiber source, ?chunk_size: Integer) -> void
      def initialize(source, chunk_size: DEFAULT_CHUNK_SIZE)
        raise ArgumentError, "lexer chunk_size must be positive" unless chunk_size.positive?
        unless source.is_a?(String) || source.respond_to?(:read) || source.is_a?(Fiber)
          raise ArgumentError, "lexer input must be a String, IO, or Fiber"
        end

        @source = source
        @chunk_size = chunk_size
        @buffer = +""
        @archive = +""
        @eof = false
        return unless source.is_a?(String)

        append(source)
        @eof = true
      end

      # @rbs () -> bool
      def eof? = @eof

      # Return every source byte read so far, including the unconsumed buffer.
      # @rbs () -> String
      def source_bytes = @archive.dup

      # Read until at least one byte is added or EOF is observed.
      # @rbs () -> bool
      def read_more?
        before = @buffer.bytesize
        read_chunk until @eof || @buffer.bytesize > before
        @buffer.bytesize > before
      end

      # @rbs (String prefix) -> void
      def consume(prefix)
        raise ArgumentError, "lexer input prefix does not match the buffer" unless @buffer.start_with?(prefix)

        @buffer.slice!(0, prefix.length)
      end

      # Return one source line, reading ahead only to its line boundary.
      # @rbs (Integer line) -> String
      def source_line(line)
        raise ArgumentError, "source line must be positive" unless line.positive?

        read_more? while !@eof && @archive.count("\n") < line
        (@archive.lines[line - 1] || "").delete_suffix("\n").delete_suffix("\r")
      end

      private

      # @rbs () -> void
      def read_chunk
        source = @source
        chunk = if source.is_a?(Fiber)
                  resume_fiber(source)
                elsif source.respond_to?(:read)
                  source.read(@chunk_size)
                end
        if chunk.nil? || chunk == ""
          @eof = true
          return
        end
        raise TypeError, "lexer input chunks must be Strings" unless chunk.is_a?(String)

        text = chunk #: String
        append(text)
      end

      # @rbs (Fiber source) -> untyped
      def resume_fiber(source)
        supports_alive = source.respond_to?(:alive?)
        if supports_alive && !source.alive?
          @eof = true
          return
        end

        value = source.resume
        @eof = true if supports_alive && !source.alive?
        value
      rescue FiberError => e
        terminated = /\A(?:dead fiber called|attempt to resume a terminated fiber)\z/.match?(e.message)
        raise unless !supports_alive && terminated

        @eof = true
        nil
      end

      # @rbs (String chunk) -> void
      def append(chunk)
        @buffer << chunk
        @archive << chunk
      end
    end
  end
end
