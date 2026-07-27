# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module RaccMigration
    # Checks syntax, normalization, superclass, and runtime-coupling hazards.
    # Semantic action code is treated as opaque data and never executed.
    class Checker
      RACC_REQUIRE = %r{(?:require|require_relative)\s*\(?\s*["']racc(?:/parser)?["']} #: Regexp
      RACC_CONSTANT = /\bRacc::[A-Za-z_]\w*/ #: Regexp

      # @rbs (String source, file: String) -> Report
      def check(source, file:)
        result = Frontend::Parser.new(source, file: file, mode: :default).parse_with_diagnostics
        findings = result.diagnostics.map { |diagnostic| syntax_finding(diagnostic) }
        ast = result.ast
        return Report.new(file: file, class_name: nil, findings: findings) unless ast

        findings.concat(superclass_findings(ast))
        findings.concat(user_code_findings(ast))
        findings.concat(normalization_findings(ast))
        Report.new(file: file, class_name: ast.class_name, findings: sort_findings(findings))
      end

      private

      # @rbs (Frontend::Diagnostic diagnostic) -> Finding
      def syntax_finding(diagnostic)
        Finding.new(
          code: "racc.syntax",
          severity: :error,
          message: diagnostic.message,
          location: diagnostic.location,
          suggestion: "keep the grammar in default mode, or adopt the reported extension explicitly " \
                      "with `pragma extended`"
        )
      end

      # @rbs (Frontend::AST::Root ast) -> Array[Finding]
      def superclass_findings(ast)
        return [] unless ast.superclass&.start_with?("Racc::")

        [
          Finding.new(
            code: "racc.runtime_superclass",
            severity: :error,
            message: "generated class inherits #{ast.superclass}",
            location: ast.loc,
            suggestion: "remove the explicit Racc superclass or generate with `--superclass=Ibex::Runtime::Parser`"
          )
        ]
      end

      # @rbs (Frontend::AST::Root ast) -> Array[Finding]
      def user_code_findings(ast)
        ast.user_code.values.flatten.flat_map do |chunk|
          findings = [] #: Array[Finding]
          if chunk.code.match?(RACC_REQUIRE)
            findings << Finding.new(
              code: "racc.runtime_require",
              severity: :warning,
              message: "user code requires the racc runtime",
              location: chunk.loc,
              suggestion: "remove this require after switching generated parsers to the Ibex runtime"
            )
          end
          if chunk.code.match?(RACC_CONSTANT)
            findings << Finding.new(
              code: "racc.runtime_constant",
              severity: :warning,
              message: "user code references a Racc runtime constant",
              location: chunk.loc,
              suggestion: "replace the runtime-specific constant or keep an explicit compatibility adapter"
            )
          end
          findings
        end
      end

      # @rbs (Frontend::AST::Root ast) -> Array[Finding]
      def normalization_findings(ast)
        Normalizer.new(ast, mode: :default).normalize
        []
      rescue Ibex::Error => e
        location, message = error_location(e.message, ast.loc)
        [
          Finding.new(
            code: "racc.normalization",
            severity: :error,
            message: message,
            location: location,
            suggestion: "apply the diagnostic before generating either parser"
          )
        ]
      end

      # @rbs (String message, Frontend::Location fallback) -> [Frontend::Location, String]
      def error_location(message, fallback)
        match = message.match(/\A(.+):(\d+):(\d+): (.*)\z/m)
        return [fallback, message] unless match

        [
          Frontend::Location.new(
            file: match[1].to_s,
            line: Integer(match[2].to_s, 10),
            column: Integer(match[3].to_s, 10)
          ),
          match[4].to_s
        ]
      end

      # @rbs (Array[Finding] findings) -> Array[Finding]
      def sort_findings(findings)
        rank = { error: 0, warning: 1, info: 2 }
        findings.sort_by do |finding|
          location = finding.location
          [location&.file || "", location&.line || 0, location&.column || 0, rank.fetch(finding.severity), finding.code]
        end
      end
    end
  end
end
