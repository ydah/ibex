# frozen_string_literal: true

require_relative "../lsp"

module Ibex
  # CLI boundary for the stdio-only language server.
  module CLILSP
    private

    # @rbs (Array[String] arguments) -> Integer
    def run_lsp_command(arguments)
      settings = { help: false, stdio: false } #: Hash[Symbol, bool]
      remaining = lsp_option_parser(settings).parse(arguments)
      raise Ibex::Error, "(cli):1:1: ibex lsp does not accept file arguments" unless remaining.empty?

      if settings.fetch(:help)
        @stdout.puts(lsp_option_parser(settings))
        return 0
      end

      LSP::Server.new(stdin: @stdin, stdout: @stdout, stderr: @stderr).run
    end

    # @rbs (Hash[Symbol, bool] settings) -> OptionParser
    def lsp_option_parser(settings)
      OptionParser.new do |options|
        options.banner = "Usage: ibex lsp [--stdio]"
        options.on("--stdio", "use Content-Length framed JSON-RPC on standard IO") { settings[:stdio] = true }
        options.on("--help", "show help") { settings[:help] = true }
      end
    end
  end
end
