class Gallery::CalcParser
pragma extended
token NUMBER
preclow
  left '+' '-'
  left '*' '/'
prechigh
lexer
  skip /[[:space:]]+/
  NUMBER /(?:0|[1-9][0-9]*)(?:\.[0-9]+)?/ { |text| text.include?(".") ? Float(text) : Integer(text, 10) }
  on /[()+\-*\/]/ { |text| emit text, text }
end
rule
  document: expression { result = val[0] }
  expression: expression '+' expression { result = val[0] + val[2] }
            | expression '-' expression { result = val[0] - val[2] }
            | expression '*' expression { result = val[0] * val[2] }
            | expression '/' expression { result = val[0] / val[2] }
            | '(' expression ')' { result = val[1] }
            | NUMBER { result = val[0] }
end
