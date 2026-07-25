# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/lsp"
require "stringio"

class LSPTransportTest < Minitest::Test
  class ChunkInput
    def initialize(content, chunks)
      @content = content.b
      @chunks = chunks
    end

    def read(length)
      return if @content.empty?

      requested = [@chunks.shift || length, length, @content.bytesize].min
      @content.slice!(0, requested)
    end
  end

  def test_reads_split_headers_bodies_and_back_to_back_frames
    first = frame("jsonrpc" => "2.0", "id" => 1, "method" => "initialize")
    second = frame("jsonrpc" => "2.0", "method" => "initialized")
    transport = Ibex::LSP::Transport.new(ChunkInput.new(first + second, [1, 2, 3, 5, 8]), StringIO.new)

    assert_equal 1, transport.read_message.fetch("id")
    assert_equal "initialized", transport.read_message.fetch("method")
    assert_nil transport.read_message
  end

  def test_malformed_json_is_recoverable_after_its_framed_body
    malformed = "Content-Length: 1\r\n\r\n{"
    valid = frame("jsonrpc" => "2.0", "method" => "exit")
    transport = Ibex::LSP::Transport.new(StringIO.new(malformed + valid), StringIO.new)

    error = assert_raises(Ibex::LSP::ProtocolError) { transport.read_message }

    refute error.fatal
    assert_equal(-32_700, error.code)
    assert_equal "exit", transport.read_message.fetch("method")
  end

  def test_live_pipe_does_not_wait_for_eof_or_a_full_read_buffer
    input, writer = IO.pipe
    writer.write(frame("jsonrpc" => "2.0", "id" => 1, "method" => "initialize"))
    thread = Thread.new { Ibex::LSP::Transport.new(input, StringIO.new).read_message }

    assert thread.join(2), "transport blocked after a complete frame was available"
    assert_equal 1, thread.value.fetch("id")
  ensure
    thread&.kill
    writer&.close
    input&.close
  end

  def test_rejects_malformed_or_oversized_framing
    duplicate = "Content-Length: 2\r\nContent-Length: 2\r\n\r\n{}"
    error = assert_raises(Ibex::LSP::ProtocolError) do
      Ibex::LSP::Transport.new(StringIO.new(duplicate), StringIO.new).read_message
    end
    assert error.fatal

    oversized = "Content-Length: #{Ibex::LSP::Limits::MAX_MESSAGE_BYTES + 1}\r\n\r\n"
    error = assert_raises(Ibex::LSP::ProtocolError) do
      Ibex::LSP::Transport.new(StringIO.new(oversized), StringIO.new).read_message
    end
    assert error.fatal
    assert_match(/exceeds/, error.message)
  end

  def test_writes_byte_counted_json_and_enforces_output_limit
    output = StringIO.new
    transport = Ibex::LSP::Transport.new(StringIO.new, output)
    transport.write_message("jsonrpc" => "2.0", "result" => "😀")

    header, body = output.string.split("\r\n\r\n", 2)
    assert_equal body.bytesize, Integer(header.delete_prefix("Content-Length: "))

    huge = { "result" => "x" * Ibex::LSP::Limits::MAX_OUTPUT_BYTES }
    assert_raises(Ibex::LSP::ProtocolError) { transport.write_message(huge) }
  end

  private

  def frame(message)
    body = JSON.generate(message)
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end
end
