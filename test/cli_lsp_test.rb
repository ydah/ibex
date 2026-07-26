# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLILSPTest < Minitest::Test
  def test_help_and_separate_option_parser
    help = invoke(["lsp", "--help"])
    assert_equal 0, help.fetch(:status)
    assert_match(/Usage: ibex lsp/, help.fetch(:stdout))

    invalid = invoke(["lsp", "--algorithm=lalr"])
    assert_equal 1, invalid.fetch(:status)
    assert_match(/invalid option/, invalid.fetch(:stderr))
  end

  def test_stdio_session_transcript
    Dir.mktmpdir("ibex-cli-lsp") do |directory|
      input = [
        request(1, "initialize", "rootUri" => file_uri(directory)),
        notification("initialized"),
        request(2, "shutdown"),
        notification("exit")
      ].join

      result = invoke(["lsp", "--stdio"], stdin: input)
      messages = decode_frames(result.fetch(:stdout))

      assert_equal 0, result.fetch(:status)
      assert_empty result.fetch(:stderr)
      response_ids = messages.map { |message| message.fetch("id") }
      assert_equal [1, 2], response_ids
      assert_equal "ibex", messages.fetch(0).dig("result", "serverInfo", "name")
    end
  end

  private

  def invoke(arguments, stdin: "")
    stdout = StringIO.new
    stderr = StringIO.new
    status = Ibex::CLI.start(arguments, stdin: StringIO.new(stdin), stdout: stdout, stderr: stderr)
    { status: status, stdout: stdout.string, stderr: stderr.string }
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
end
