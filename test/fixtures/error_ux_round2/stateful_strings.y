class ErrorUXRound2::StatefulStringParser
pragma extended
token STRING_BEGIN STRING_TEXT STRING_END
lexer
  skip /\s+/
  state STRING do
    on /"/ { pop_state; emit :STRING_END, nil }
    STRING_TEXT /[^"\n]+/ { |source| source }
  end
  on /"/ { push_state :STRING; emit :STRING_BEGIN, nil }
end
rule
document: STRING_BEGIN STRING_TEXT STRING_END { result = val[1] }
end
---- inner
def parse(source, file: "(h003-stateful-string)") = super
