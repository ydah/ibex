class LexerProfileNestedQuantifierParser
pragma extended
pragma cst
token WORD
lexer
  WORD /(a+)+b/
end
rule
start: WORD
end
