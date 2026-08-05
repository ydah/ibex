class ErrorUXRound2::DelimiterParser
pragma extended
token NAME
lexer
  skip /\s+/
  NAME /[a-z]+/
  on /[(),\[\]]/ { |source| emit source, nil }
end
rule
document: call { result = val[0] }
call: NAME '(' arguments ')' { result = [val[0], val[2]] }
arguments: argument { result = [val[0]] }
         | arguments ',' argument { result = val[0] + [val[2]] }
argument: NAME { result = val[0] }
        | call { result = val[0] }
end
---- inner
def parse(source, file: "(h003-delimiters)") = super
