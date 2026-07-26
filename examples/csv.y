class Examples::CSVParser
pragma extended
token FIELD NEWLINE
%test accept "name,age\n\"Doe, Jane\",36\n"
%test reject "name,age"
lexer
  FIELD /"(?:[^"]|"")*"|[^,\r\n]+/ { |source| decode_csv_field(source) }
  NEWLINE /\r\n|\n|\r/
  on /,/ { |source| emit source, nil }
end
rule
  document : rows { result = val[0] }
  rows     : rows row { result = val[0] + [val[1]] }
           | row { result = [val[0]] }
  row      : fields NEWLINE { result = val[0] }
  fields   : fields ',' field { result = val[0] + [val[2]] }
           | field { result = [val[0]] }
  field    : FIELD { result = val[0] }
end
---- inner
def parse(source, file: "(csv)") = super

def decode_csv_field(source)
  return source unless source.start_with?('"')

  source[1...-1].gsub('""', '"')
end
---- footer
if $PROGRAM_NAME == __FILE__
  require "json"
  puts JSON.generate(Examples::CSVParser.new.parse(ARGF.read))
end
