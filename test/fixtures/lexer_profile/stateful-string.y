class LexerProfileStatefulStringParser
pragma extended
pragma cst
token CONTENT
lexer
  on /"/ { self.lexer_state = :STRING; skip }
  state STRING do
    CONTENT /[^"\n]+/
    on /"/ { self.lexer_state = :INITIAL; skip }
  end
end
rule
start: CONTENT
end
