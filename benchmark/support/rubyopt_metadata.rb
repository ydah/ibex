# frozen_string_literal: true

require "digest"
require "shellwords"

module BenchmarkSupport
  # Records RUBYOPT identity and option shape without retaining values or paths.
  module RubyoptMetadata
    module_function

    def build(raw)
      return { present: false, bytes: 0, sha256: nil, sanitized: [] } if raw.nil?

      {
        present: true,
        bytes: raw.bytesize,
        sha256: Digest::SHA256.hexdigest(raw),
        sanitized: sanitized(raw)
      }
    end

    def sanitized(raw)
      Shellwords.split(raw).map { |token| sanitize_token(token) }
    rescue ArgumentError
      ["<malformed-redacted>"]
    end

    def sanitize_token(token)
      return token if token.match?(/\A--?(?:disable-|enable-)?(?:gems|jit|yjit)\z/)
      return token if token.match?(/\A-[Ww]\d?\z/)

      match = token.match(/\A(--?[A-Za-z][A-Za-z0-9-]*)=/)
      return "#{match[1]}=<redacted>" if match

      match = token.match(/\A(-[Irx]).+/)
      return "#{match[1]}<redacted>" if match
      return token if token.match?(/\A--?[A-Za-z][A-Za-z0-9-]*\z/)

      "<redacted>"
    end
  end
end
