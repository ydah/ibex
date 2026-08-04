# frozen_string_literal: true

module Ibex
  module Quality
    # Rejects cross-category scores/rankings while permitting one explicit policy explanation.
    module ComparativeWording
      FORBIDDEN = /(?:
        \b(?:aggregate|combined|overall|total)\s+(?:score|scores|ranking|rankings)\b |
        \brank(?:ing|ings)?(?:\s+table)?\b |
        総合(?:点|スコア|評価|順位|ランキング) |
        (?:順位|ランキング)表 |
        合算(?:点|スコア|評価)
      )/ix
      ALLOWANCE = /
        <!--\s+comparison-policy:forbidden-terms:start\s+-->
        .*?
        <!--\s+comparison-policy:forbidden-terms:end\s+-->
      /mx

      module_function

      def verify!(source, path:, policy: false)
        if source.include?("comparison-policy:forbidden-terms") && !policy
          raise "#{path}: forbidden-term allowance is restricted to the comparison policy"
        end

        checked = policy ? source.gsub(ALLOWANCE, "") : source
        if checked.include?("comparison-policy:forbidden-terms")
          raise "#{path}: malformed forbidden-term policy allowance"
        end

        match = checked.match(FORBIDDEN)
        raise "#{path}: combined scores and rankings are forbidden: #{match[0]}" if match
      end
    end
  end
end
