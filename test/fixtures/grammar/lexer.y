class Fixture::LexerParser
pragma extended
token NUM STR_BEGIN STR_END CHUNK
lexer
  skip /\s+/
  NUM /\d+/ { |s| s.to_i }
  state STRING do
    on '"' { pop_state; emit :STR_END }
    CHUNK /[^"\\]+/
  end
  on '"' { push_state :STRING; emit :STR_BEGIN }
end
rule
value: NUM | STR_BEGIN CHUNK STR_END
end
