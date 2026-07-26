class Examples::JSONParser
pragma extended
token STRING NUMBER TRUE FALSE NULL
%test accept "{\"ok\":[true,null]}"
%test reject "{\"ok\":}"
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
  @json_source = source
  @scanner = StringScanner.new(source)
  do_parse
end

def next_token
  @scanner.skip(/\s+/)
  return false if @scanner.eos?

  start_byte = @scanner.pos
  if (punctuation = @scanner.scan(/[{}\[\],:]/))
    located_token(punctuation, nil, start_byte)
  elsif (string = @scanner.scan(/"(?:\\(?:["\\\/bfnrt]|u[0-9a-fA-F]{4})|[^"\\])*"/))
    located_token(:STRING, decode_json_string(string), start_byte)
  elsif (number = @scanner.scan(/-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/))
    located_token(:NUMBER, number.match?(/[.eE]/) ? Float(number) : Integer(number, 10), start_byte)
  elsif @scanner.scan(/true/)
    located_token(:TRUE, true, start_byte)
  elsif @scanner.scan(/false/)
    located_token(:FALSE, false, start_byte)
  elsif @scanner.scan(/null/)
    located_token(:NULL, nil, start_byte)
  else
    raise ArgumentError, "unexpected JSON input at offset #{@scanner.pos}"
  end
end

def located_token(token, value, start_byte)
  ending = @scanner.pos
  start_line, start_column = json_coordinates(start_byte)
  end_line, end_column = json_coordinates(ending)
  location = {
    file: "(json)", line: start_line, column: start_column,
    end_line: end_line, end_column: end_column,
    start_byte: start_byte, end_byte: ending,
    source_line: @json_source.lines.fetch(start_line - 1, "").chomp
  }
  [token, value, location]
end

def json_coordinates(byte_offset)
  prefix = @json_source.byteslice(0, byte_offset)
  [prefix.count("\n") + 1, prefix.rpartition("\n").last.each_char.count + 1]
end

def decode_json_string(source)
  JSON.parse(source)
end
---- footer
if $PROGRAM_NAME == __FILE__
  puts JSON.generate(Examples::JSONParser.new.parse(ARGF.read))
end
