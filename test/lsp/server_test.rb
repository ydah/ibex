# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/lsp"
require "stringio"
require "tmpdir"

class LSPServerTest < Minitest::Test
  # rubocop:disable Metrics/AbcSize, Metrics/BlockLength -- one transcript verifies framing and lifecycle together.
  def test_full_session_keeps_stdout_framed_and_exits_cleanly
    Dir.mktmpdir("ibex-lsp-server") do |directory|
      path = File.join(directory, "grammar.y")
      source = "class P\ntoken TOKEN\nrule\nstart: TOKEN\nend\n"
      File.binwrite(path, source)
      uri = file_uri(path)
      input = [
        request(1, "initialize", "rootUri" => file_uri(directory)),
        notification("initialized"),
        notification("textDocument/didOpen", open_params(uri, source, 1)),
        request(2, "textDocument/definition", text_position(uri, 3, 8)),
        request(3, "shutdown"),
        notification("exit")
      ].join
      stdout = StringIO.new
      stderr = StringIO.new

      status = Ibex::LSP::Server.new(
        stdin: StringIO.new(input), stdout: stdout, stderr: stderr
      ).run
      messages = decode_frames(stdout.string)

      assert_equal 0, status
      assert_empty stderr.string
      response_ids = messages.map { |message| message["id"] }
      assert_equal [1, nil, 2, 3], response_ids
      assert_equal "utf-16", messages.fetch(0).dig("result", "capabilities", "positionEncoding")
      assert_equal "textDocument/publishDiagnostics", messages.fetch(1).fetch("method")
      assert_equal uri, messages.fetch(2).dig("result", 0, "uri")
      assert_nil messages.fetch(3).fetch("result")
      assert stdout.string.scan("Content-Length:").length == messages.length
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/BlockLength

  def test_lifecycle_unknown_method_and_exit_status
    Dir.mktmpdir("ibex-lsp-server") do |directory|
      input = [
        request(1, "shutdown"),
        notification("exit")
      ].join
      stdout = StringIO.new
      status = Ibex::LSP::Server.new(
        stdin: StringIO.new(input), stdout: stdout, stderr: StringIO.new
      ).run

      assert_equal 1, status
      assert_equal(-32_002, decode_frames(stdout.string).fetch(0).dig("error", "code"))

      input = [
        request(1, "initialize", "rootUri" => file_uri(directory)),
        notification("initialized"),
        request(2, "unknown/method"),
        request(3, "shutdown"),
        notification("exit")
      ].join
      stdout = StringIO.new
      status = Ibex::LSP::Server.new(
        stdin: StringIO.new(input), stdout: stdout, stderr: StringIO.new
      ).run
      unknown = decode_frames(stdout.string).find { |message| message["id"] == 2 }

      assert_equal 0, status
      assert_equal(-32_601, unknown.dig("error", "code"))
    end
  end

  def test_malformed_json_emits_parse_error_and_continues
    Dir.mktmpdir("ibex-lsp-server") do |directory|
      malformed = "Content-Length: 1\r\n\r\n{"
      input = malformed + [
        request(1, "initialize", "rootUri" => file_uri(directory)),
        notification("initialized"),
        request(2, "shutdown"),
        notification("exit")
      ].join
      stdout = StringIO.new

      status = Ibex::LSP::Server.new(
        stdin: StringIO.new(input), stdout: stdout, stderr: StringIO.new
      ).run
      messages = decode_frames(stdout.string)

      assert_equal 0, status
      assert_equal(-32_700, messages.fetch(0).dig("error", "code"))
      assert_nil messages.fetch(0)["id"]
      response_ids = messages.drop(1).map { |message| message.fetch("id") }
      assert_equal [1, 2], response_ids
    end
  end

  def test_did_change_requires_full_text_and_monotonic_version
    Dir.mktmpdir("ibex-lsp-server") do |directory|
      path = File.join(directory, "grammar.y")
      source = "class P\nrule\nstart: TOKEN\nend\n"
      File.binwrite(path, source)
      uri = file_uri(path)
      input = [
        request(1, "initialize", "rootUri" => file_uri(directory)),
        notification("initialized"),
        notification("textDocument/didOpen", open_params(uri, source, 2)),
        notification(
          "textDocument/didChange",
          "textDocument" => { "uri" => uri, "version" => 2 },
          "contentChanges" => [{ "text" => source }]
        ),
        request(3, "shutdown"),
        notification("exit")
      ].join
      stderr = StringIO.new

      status = Ibex::LSP::Server.new(
        stdin: StringIO.new(input), stdout: StringIO.new, stderr: stderr
      ).run

      assert_equal 0, status
      assert_match(/version must increase monotonically/, stderr.string)
    end
  end

  def test_unknown_dollar_notification_is_ignored_and_eof_after_shutdown_is_abnormal
    Dir.mktmpdir("ibex-lsp-server") do |directory|
      input = [
        request(1, "initialize", "rootUri" => file_uri(directory)),
        notification("initialized"),
        notification("$/unknownExtension"),
        request(2, "shutdown")
      ].join
      stdout = StringIO.new
      stderr = StringIO.new

      status = Ibex::LSP::Server.new(
        stdin: StringIO.new(input), stdout: stdout, stderr: stderr
      ).run

      assert_equal 1, status
      assert_empty stderr.string
      response_ids = decode_frames(stdout.string).map { |message| message.fetch("id") }
      assert_equal [1, 2], response_ids
    end
  end

  def test_invalid_workspace_folder_entry_is_an_invalid_params_error
    input = request(1, "initialize", "workspaceFolders" => ["not-an-object"])
    stdout = StringIO.new

    status = Ibex::LSP::Server.new(
      stdin: StringIO.new(input), stdout: stdout, stderr: StringIO.new
    ).run
    response = decode_frames(stdout.string).fetch(0)

    assert_equal 1, status
    assert_equal(-32_602, response.dig("error", "code"))
    assert_match(/workspaceFolders entries must be objects/, response.dig("error", "message"))
  end

  def test_invalid_envelopes_receive_request_errors_with_safe_ids
    input = [
      frame("jsonrpc" => "2.0", "id" => 7),
      frame("jsonrpc" => "2.0", "id" => { "unsafe" => true }, "method" => "initialize")
    ].join
    stdout = StringIO.new

    status = Ibex::LSP::Server.new(
      stdin: StringIO.new(input), stdout: stdout, stderr: StringIO.new
    ).run
    responses = decode_frames(stdout.string)
    response_ids = responses.map { |response| response["id"] }
    response_codes = responses.map { |response| response.dig("error", "code") }

    assert_equal 1, status
    assert_equal [7, nil], response_ids
    assert_equal [-32_600, -32_600], response_codes
  end

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
    "file://#{URI::RFC2396_PARSER.escape(path)}"
  end

  def open_params(uri, source, version)
    {
      "textDocument" => {
        "uri" => uri, "languageId" => "ibex", "version" => version, "text" => source
      }
    }
  end

  def text_position(uri, line, character)
    { "textDocument" => { "uri" => uri }, "position" => { "line" => line, "character" => character } }
  end
end
