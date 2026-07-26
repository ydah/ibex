class ErrorUXJSONRaccParser
token STRING NUMBER TRUE FALSE NULL
rule
  document : value
  value    : object
           | array
           | STRING
           | NUMBER
           | TRUE
           | FALSE
           | NULL
  object   : '{' '}'
           | '{' members '}'
  members  : pair
           | members ',' pair
  pair     : STRING ':' value
  array    : '[' ']'
           | '[' elements ']'
  elements : value
           | elements ',' value
end
---- header
require "strscan"

class ErrorUXRaccParseError < StandardError
  attr_reader :token, :value

  def initialize(token, value)
    @token = token
    @value = value
    super("unexpected #{token.inspect} (#{value.inspect})")
  end
end
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
    [:STRING, string]
  elsif (number = @scanner.scan(/-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/))
    [:NUMBER, number]
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

def on_error(token, value, _value_stack)
  raise ErrorUXRaccParseError.new(token, value)
end
