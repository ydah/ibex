class Examples::CalculatorParser
token NUMBER
rule
  expression : expression '+' term { result = val[0] + val[2] }
             | expression '-' term { result = val[0] - val[2] }
             | term { result = val[0] }
  term       : term '*' factor { result = val[0] * val[2] }
             | term '/' factor { result = val[0] / val[2] }
             | factor { result = val[0] }
  factor     : NUMBER { result = val[0] }
             | '(' expression ')' { result = val[1] }
end
---- header
require "strscan"
---- inner
def parse(source)
  @scanner = StringScanner.new(source)
  do_parse
end

def next_token
  @scanner.skip(/\s+/)
  return false if @scanner.eos?

  if (number = @scanner.scan(/\d+/))
    [:NUMBER, Integer(number, 10)]
  elsif (operator = @scanner.scan(/[()+*\/-]/))
    [operator, nil]
  else
    raise ArgumentError, "unexpected calculator input at offset #{@scanner.pos}"
  end
end
---- footer
if $PROGRAM_NAME == __FILE__
  abort "usage: ruby calculator.rb EXPRESSION" if ARGV.empty?

  puts Examples::CalculatorParser.new.parse(ARGV.join(" "))
end
