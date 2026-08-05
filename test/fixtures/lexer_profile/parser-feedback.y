class LexerProfileParserFeedbackParser
pragma extended
pragma cst
token HEAD TAIL
lexer
  HEAD /head/
  state AFTER do
    TAIL /tail/
  end
end
rule
start: prefix TAIL
prefix: HEAD { self.lexer_state = :AFTER }
end
