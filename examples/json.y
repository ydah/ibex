class Examples::JSONParser
pragma extended
token STRING NUMBER TRUE FALSE NULL
%test accept "{\"ok\":[true,null]}"
%test reject "{\"ok\":}"
lexer
  skip /\s+/
  STRING /"(?:\\(?:["\\\/bfnrt]|u[0-9a-fA-F]{4})|[^"\\])*"/ { |source| decode_json_string(source) }
  NUMBER /-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/ {
    |source| source.match?(/[.eE]/) ? Float(source) : Integer(source, 10)
  }
  TRUE /true/ { true }
  FALSE /false/ { false }
  NULL /null/ { nil }
  on /[{}\[\],:]/ { |source| emit source, nil }
end
rule
  document : value { result = val[0] }
  value    : object { result = val[0] }
           | array { result = val[0] }
           | STRING { result = val[0] }
           | NUMBER { result = val[0] }
           | TRUE { result = true }
           | FALSE { result = false }
           | NULL { result = nil }
  object   : '{' '}' { result = {} }
           | '{' members '}' { result = val[1] }
  members  : pair { result = { val[0][0] => val[0][1] } }
           | members ',' pair { result = val[0].merge(val[2][0] => val[2][1]) }
  pair     : STRING ':' value { result = [val[0], val[2]] }
  array    : '[' ']' { result = [] }
           | '[' elements ']' { result = val[1] }
  elements : value { result = [val[0]] }
           | elements ',' value { result = val[0] + [val[2]] }
end
---- header
require "json"
---- inner
def parse(source, file: "(json)") = super

def decode_json_string(source)
  JSON.parse(source)
end
---- footer
if $PROGRAM_NAME == __FILE__
  puts JSON.generate(Examples::JSONParser.new.parse(ARGF.read))
end
