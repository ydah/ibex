class LexerProfileLazyParser
pragma extended
pragma cst
token A
lexer
  A /a+?/
end
rule
start: A A A
end
