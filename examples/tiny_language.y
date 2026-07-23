class Examples::TinyLanguageParser
token IDENTIFIER NUMBER PRINT
rule
  program    : statements { result = val[0] }
  statements : statements statement { result = val[0] + [val[1]] }
             | { result = [] }
  statement  : IDENTIFIER '=' expression ';' { result = [:assign, val[0], val[2]] }
             | PRINT expression ';' { result = [:print, val[1]] }
  expression : expression '+' term { result = [:add, val[0], val[2]] }
             | expression '-' term { result = [:subtract, val[0], val[2]] }
             | term { result = val[0] }
  term       : term '*' factor { result = [:multiply, val[0], val[2]] }
             | term '/' factor { result = [:divide, val[0], val[2]] }
             | factor { result = val[0] }
  factor     : NUMBER { result = [:number, val[0]] }
             | IDENTIFIER { result = [:variable, val[0]] }
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

  if @scanner.scan(/print\b/)
    [:PRINT, "print"]
  elsif (identifier = @scanner.scan(/[A-Za-z_][A-Za-z0-9_]*/))
    [:IDENTIFIER, identifier]
  elsif (number = @scanner.scan(/\d+/))
    [:NUMBER, Integer(number, 10)]
  elsif (punctuation = @scanner.scan(/[=;()+*\/-]/))
    [punctuation, nil]
  else
    raise ArgumentError, "unexpected language input at offset #{@scanner.pos}"
  end
end

def execute(statements, output: $stdout)
  environment = {}
  statements.each do |statement|
    case statement[0]
    when :assign
      environment[statement[1]] = evaluate_expression(statement[2], environment)
    when :print
      output.puts(evaluate_expression(statement[1], environment))
    end
  end
  environment
end

def evaluate_expression(expression, environment)
  case expression[0]
  when :number then expression[1]
  when :variable then environment.fetch(expression[1])
  when :add then evaluate_expression(expression[1], environment) + evaluate_expression(expression[2], environment)
  when :subtract then evaluate_expression(expression[1], environment) - evaluate_expression(expression[2], environment)
  when :multiply then evaluate_expression(expression[1], environment) * evaluate_expression(expression[2], environment)
  when :divide then evaluate_expression(expression[1], environment) / evaluate_expression(expression[2], environment)
  end
end
---- footer
if $PROGRAM_NAME == __FILE__
  parser = Examples::TinyLanguageParser.new
  parser.execute(parser.parse(ARGF.read))
end
