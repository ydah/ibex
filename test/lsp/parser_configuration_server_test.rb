# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/lsp"
require "stringio"
require "tmpdir"

class LSPParserConfigurationServerTest < Minitest::Test
  # One framed transcript must retain the request and both responses together.
  # rubocop:disable Metrics/AbcSize
  def test_completion_and_hover_requests_are_routed
    Dir.mktmpdir("ibex-lsp-server") do |directory|
      path = File.join(directory, "grammar.y")
      source = "class P\nparser\n  algorithm ielr\nend\nrule\nstart: TOKEN\nend\n"
      File.binwrite(path, source)
      uri = file_uri(path)
      input = [
        request(1, "initialize", "rootUri" => file_uri(directory)),
        notification("initialized"),
        notification("textDocument/didOpen", open_params(uri, source, 1)),
        request(2, "textDocument/completion", text_position(uri, 2, 12)),
        request(3, "textDocument/hover", text_position(uri, 2, 13)),
        request(4, "shutdown"),
        notification("exit")
      ].join
      stdout = StringIO.new

      status = Ibex::LSP::Server.new(stdin: StringIO.new(input), stdout: stdout, stderr: StringIO.new).run
      messages = decode_frames(stdout.string)
      completion = messages.find { |message| message["id"] == 2 }
      hover = messages.find { |message| message["id"] == 3 }
      labels = completion.dig("result", "items").map { |item| item["label"] }

      assert_equal 0, status
      assert_equal %w[slr lalr ielr lr1], labels
      assert_includes hover.dig("result", "contents", "value"), "IELR"
    end
  end
  # rubocop:enable Metrics/AbcSize

  private

  def request(id, method, params = nil)
    message = { "jsonrpc" => "2.0", "id" => id, "method" => method }
    message["params"] = params if params
    frame(message)
  end

  def notification(method, params = nil)
    message = { "jsonrpc" => "2.0", "method" => method }
    message["params"] = params if params
    frame(message)
  end

  def frame(message)
    body = JSON.generate(message)
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  def decode_frames(content)
    transport = Ibex::LSP::Transport.new(StringIO.new(content), StringIO.new)
    messages = []
    loop do
      message = transport.read_message
      break unless message

      messages << message
    end
    messages
  end

  def file_uri(path)
    "file://#{TestURI::PARSER.escape(path)}"
  end

  def open_params(uri, source, version)
    { "textDocument" => { "uri" => uri, "languageId" => "ibex", "version" => version, "text" => source } }
  end

  def text_position(uri, line, character)
    { "textDocument" => { "uri" => uri }, "position" => { "line" => line, "character" => character } }
  end
end
