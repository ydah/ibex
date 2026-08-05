class ErrorUXRound2::StatementParser
pragma extended
token NAME NUMBER PRINT
%recover sync: ';'
lexer
  skip /\s+/
  PRINT /print\b/ { :print }
  NAME /[a-z]+/ { |source| source }
  NUMBER /\d+/ { |source| Integer(source, 10) }
  on /[=;]/ { |source| emit source, nil }
end
rule
program: statements { result = val[0] }
statements: statements statement { result = val[0] + [val[1]] }
          | { result = [] }
statement: NAME '=' NUMBER ';' { result = [:assign, val[0], val[2]] }
         | PRINT NAME ';' { result = [:print, val[1]] }
         | error ';' { result = [:invalid] }
end
---- inner
def parse(source, file: "(h003-statements)") = super
