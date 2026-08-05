class LexerProfileAlternationParser
pragma extended
pragma cst
token A B
lexer
  A /a|ab/
  B /b/
end
rule
start: A B
end
