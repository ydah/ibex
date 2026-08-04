# frozen_string_literal: true

module Ibex
  module Quality
    # Rejects obvious placeholders and mechanically repeated rationale filler.
    module RuntimeABIAssessmentRationale
      PLACEHOLDERS = %w[todo tbd fixme template placeholder].freeze
      PLACEHOLDER_TOKEN = Regexp.new(
        "(?<![\\p{L}\\p{N}])(?:#{PLACEHOLDERS.join('|')})(?![\\p{L}\\p{N}])"
      )
      OBFUSCATED_PLACEHOLDERS = PLACEHOLDERS.map do |placeholder|
        characters = placeholder.chars.map { |character| Regexp.escape(character) }
        Regexp.new("(?<![\\p{L}\\p{N}])#{characters.join('[^\\p{L}\\p{N}]*')}(?![\\p{L}\\p{N}])")
      end.freeze
      ERROR = "runtime ABI assessment rationale must be substantive and must replace the placeholder"

      def self.verify!(value)
        raise ERROR unless value.is_a?(String)

        normalized = value.unicode_normalize(:nfkc).downcase
        raise ERROR if normalized.match?(/\p{Cf}/u) || placeholder?(normalized)
        raise ERROR unless diverse_prose?(normalized)
      end

      def self.diverse_prose?(text)
        alnum = text.scan(/[\p{L}\p{N}]/u)
        letters = text.scan(/\p{L}/u)
        tokens = text.scan(/[\p{L}\p{N}]+/u)

        alnum.length >= 20 && letters.length >= 12 && alnum.uniq.length >= 8 &&
          letters.uniq.length >= 6 && alnum.uniq.length * 5 >= alnum.length &&
          !repeated_token_filler?(tokens) && !periodic_filler?(alnum.join)
      end
      private_class_method :diverse_prose?

      def self.placeholder?(text)
        text.match?(PLACEHOLDER_TOKEN) || OBFUSCATED_PLACEHOLDERS.any? { |pattern| text.match?(pattern) }
      end
      private_class_method :placeholder?

      def self.repeated_token_filler?(tokens)
        return false if tokens.length < 4

        tokens.tally.values.max.to_i * 2 >= tokens.length
      end
      private_class_method :repeated_token_filler?

      def self.periodic_filler?(text)
        maximum = [text.length / 3, 24].min
        (1..maximum).any? do |width|
          text.length.remainder(width).zero? && text == text[0, width] * (text.length / width)
        end
      end
      private_class_method :periodic_filler?
    end
  end
end
