class Examples::INIParser
token SECTION KEY VALUE NEWLINE
rule
  document : lines { result = build_document(val[0]) }
  lines    : lines line { result = val[1] ? val[0] + [val[1]] : val[0] }
           | { result = [] }
  line     : SECTION NEWLINE { result = [:section, val[0]] }
           | KEY '=' VALUE NEWLINE { result = [:entry, val[0], val[2]] }
           | NEWLINE { result = nil }
end
---- header
require "strscan"
---- inner
def parse(source)
  @tokens = tokenize_ini(source)
  do_parse
end

def next_token
  @tokens.shift || false
end

def tokenize_ini(source)
  source.lines.flat_map.with_index(1) do |line, line_number|
    scanner = StringScanner.new(line.chomp)
    scanner.skip(/\s*/)
    if scanner.eos? || scanner.peek(1).match?(/[;#]/)
      [[:NEWLINE, nil]]
    elsif scanner.scan(/\[/)
      name = scanner.scan(/[^\]]+/)&.strip
      closer = scanner.scan(/\]/)
      scanner.skip(/\s*/)
      invalid_ini_line!(line_number) unless name && !name.empty? && closer && scanner.eos?
      [[:SECTION, name], [:NEWLINE, nil]]
    else
      key = scanner.scan(/[A-Za-z0-9_.-]+/)
      scanner.skip(/\s*/)
      separator = scanner.scan(/=/)
      scanner.skip(/\s*/)
      value = scanner.rest.strip
      invalid_ini_line!(line_number) unless key && separator
      [[:KEY, key], ["=", nil], [:VALUE, value], [:NEWLINE, nil]]
    end
  end
end

def invalid_ini_line!(line_number)
  raise ArgumentError, "invalid INI input on line #{line_number}"
end

def build_document(records)
  document = {}
  current = document
  records.each do |record|
    if record[0] == :section
      current = (document[record[1]] ||= {})
    else
      current[record[1]] = record[2]
    end
  end
  document
end
---- footer
if $PROGRAM_NAME == __FILE__
  require "json"
  puts JSON.generate(Examples::INIParser.new.parse(ARGF.read))
end
