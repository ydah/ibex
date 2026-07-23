class Examples::JSONParser
token STRING NUMBER TRUE FALSE NULL
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
require "strscan"
---- inner
def parse(source)
  @scanner = StringScanner.new(source)
  do_parse
end

def next_token
  @scanner.skip(/\s+/)
  return false if @scanner.eos?

  if (punctuation = @scanner.scan(/[{}\[\],:]/))
    [punctuation, nil]
  elsif (string = @scanner.scan(/"(?:\\(?:["\\\/bfnrt]|u[0-9a-fA-F]{4})|[^"\\])*"/))
    [:STRING, decode_json_string(string)]
  elsif (number = @scanner.scan(/-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/))
    [:NUMBER, number.match?(/[.eE]/) ? Float(number) : Integer(number, 10)]
  elsif @scanner.scan(/true/)
    [:TRUE, true]
  elsif @scanner.scan(/false/)
    [:FALSE, false]
  elsif @scanner.scan(/null/)
    [:NULL, nil]
  else
    raise ArgumentError, "unexpected JSON input at offset #{@scanner.pos}"
  end
end

def decode_json_string(source)
  JSON.parse(source)
end
---- footer
if $PROGRAM_NAME == __FILE__
  puts JSON.generate(Examples::JSONParser.new.parse(ARGF.read))
end
