class LexerProfileCommonPrefixParser
pragma extended
pragma cst
token LEFT RIGHT
lexer
  LEFT /aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/
  RIGHT /aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab/
end
rule
start: RIGHT
end
