class LexerProfileChunkBoundaryParser
pragma extended
pragma cst
token WORD
lexer
  WORD /[a-z]+/
end
rule
start: WORD
end
