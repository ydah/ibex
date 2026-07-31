class Gallery::JSONParser
pragma extended
token STRING NUMBER TRUE FALSE NULL
lexer
  skip /[[:space:]]+/
  STRING /"(?:\\(?:["\\\/bfnrt]|u[0-9a-fA-F]{4})|[^"\\])*"/ { |text| JSON.parse(text) }
  NUMBER /-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/ {
    |text| text.match?(/[.eE]/) ? Float(text) : Integer(text, 10)
  }
  TRUE /true/ { true }
  FALSE /false/ { false }
  NULL /null/ { nil }
  on /[{}\[\],:]/ { |text| emit text, text }
end
rule
  document: value { result = val[0] }
  value: object { result = val[0] }
       | array { result = val[0] }
       | STRING { result = val[0] }
       | NUMBER { result = val[0] }
       | TRUE { result = true }
       | FALSE { result = false }
       | NULL { result = nil }
  object: '{' '}' { result = {} }
        | '{' members '}' { result = val[1] }
  members: pair { result = { val[0][0] => val[0][1] } }
         | members ',' pair { result = val[0].merge(val[2][0] => val[2][1]) }
  pair: STRING ':' value { result = [val[0], val[2]] }
  array: '[' ']' { result = [] }
       | '[' elements ']' { result = val[1] }
  elements: value { result = [val[0]] }
          | elements ',' value { result = val[0] + [val[2]] }
end
---- header
require "json"
