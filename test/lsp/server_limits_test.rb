# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/lsp"
require "stringio"
require "tmpdir"

class LSPServerLimitsTest < Minitest::Test
  def test_near_limit_unknown_method_still_receives_a_bounded_method_not_found_response
    Dir.mktmpdir("ibex-lsp-server") do |directory|
      method = "x" * (Ibex::LSP::Limits::MAX_MESSAGE_BYTES - 128)
      input = session(directory, method)
      stdout = StringIO.new

      status = Ibex::LSP::Server.new(
        stdin: StringIO.new(input), stdout: stdout, stderr: StringIO.new
      ).run
      unknown = decode_frames(stdout.string).find { |response| response["id"] == 2 }

      assert_equal 0, status
      assert_equal(-32_601, unknown.dig("error", "code"))
      assert_operator unknown.dig("error", "message").bytesize, :<, 8 * 1024
      assert_operator stdout.string.bytesize, :<=, Ibex::LSP::Limits::MAX_OUTPUT_BYTES
    end
  end

  def test_oversized_request_id_is_rejected_without_echoing_it
    oversized_id = "i" * (Ibex::LSP::Limits::MAX_REQUEST_ID_BYTES + 1)
    input = request(oversized_id, "initialize", "rootUri" => "file:///unused")
    stdout = StringIO.new

    status = Ibex::LSP::Server.new(
      stdin: StringIO.new(input), stdout: stdout, stderr: StringIO.new
    ).run
    response = decode_frames(stdout.string).fetch(0)

    assert_equal 1, status
    assert_nil response["id"]
    assert_equal(-32_600, response.dig("error", "code"))
  end

  private

  def session(directory, method)
    [
      request(1, "initialize", "rootUri" => file_uri(directory)),
      notification("initialized"),
      request(2, method),
      request(3, "shutdown"),
      notification("exit")
    ].join
  end

  def request(id, method, params = nil)
    message = { "jsonrpc" => "2.0", "id" => id, "method" => method }
    message["params"] = params if params
    frame(message)
  end

  def notification(method)
    frame("jsonrpc" => "2.0", "method" => method)
  end

  def frame(message)
    body = JSON.generate(message)
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  def decode_frames(content)
    transport = Ibex::LSP::Transport.new(StringIO.new(content), StringIO.new)
    [].tap do |messages|
      while (message = transport.read_message)
        messages << message
      end
    end
  end

  def file_uri(path)
    "file://#{TestURI::PARSER.escape(path)}"
  end
end
