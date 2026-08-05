class LexerProfileUnicodeParser
pragma extended
pragma cst
token WORD
lexer
  WORD /\p{Letter}+/
end
rule
start: WORD
end
