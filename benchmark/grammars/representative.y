class BenchmarkRepresentativeParser
token IDENTIFIER NUMBER STRING
token IMPORT FROM AS TYPE ENUM FN LET CONST
token IF ELSE WHILE FOR IN BREAK CONTINUE RETURN
token MATCH CASE DEFAULT TRUE FALSE NULL
token OR AND EQ NE LE GE ARROW
expect 0
preclow
left OR
left AND
nonassoc EQ NE '<' '>' LE GE
left '+' '-'
left '*' '/' '%'
right '!' UMINUS
prechigh
rule
  program
    : declarations { result = val[0] }

  declarations
    : declarations declaration { result = val[0] + val[1] }
    | { result = 0 }

  declaration
    : import_declaration { result = 1 }
    | type_declaration { result = 1 }
    | enum_declaration { result = 1 }
    | function_declaration { result = 1 }
    | binding_declaration { result = 1 }

  import_declaration
    : IMPORT import_path import_alias ';'
    | FROM import_path IMPORT import_names ';'

  import_path
    : IDENTIFIER
    | import_path '.' IDENTIFIER

  import_alias
    : AS IDENTIFIER
    |

  import_names
    : import_name
    | import_names ',' import_name

  import_name
    : IDENTIFIER import_alias

  type_declaration
    : TYPE IDENTIFIER type_parameters '=' type_expression ';'

  enum_declaration
    : ENUM IDENTIFIER type_parameters '{' enum_variants '}'

  enum_variants
    : enum_variant
    | enum_variants ',' enum_variant

  enum_variant
    : IDENTIFIER
    | IDENTIFIER '(' type_list ')'

  type_parameters
    : '<' identifier_list '>'
    |

  type_expression
    : named_type
    | tuple_type
    | array_type
    | function_type

  named_type
    : IDENTIFIER
    | IDENTIFIER '<' type_list '>'

  tuple_type
    : '(' type_list ')'

  array_type
    : '[' type_expression ']'

  function_type
    : FN '(' optional_type_list ')' ARROW type_expression

  type_list
    : type_expression
    | type_list ',' type_expression

  optional_type_list
    : type_list
    |

  function_declaration
    : FN IDENTIFIER type_parameters '(' optional_parameters ')' return_type block

  optional_parameters
    : parameters
    |

  parameters
    : parameter
    | parameters ',' parameter

  parameter
    : IDENTIFIER ':' type_expression default_value

  default_value
    : '=' expression
    |

  return_type
    : ARROW type_expression
    |

  binding_declaration
    : binding_kind binding_list ';'

  binding_kind
    : LET
    | CONST

  binding_list
    : binding
    | binding_list ',' binding

  binding
    : IDENTIFIER type_annotation '=' expression

  type_annotation
    : ':' type_expression
    |

  block
    : '{' statements '}'

  statements
    : statements statement
    |

  statement
    : block
    | binding_declaration
    | expression_statement
    | if_statement
    | while_statement
    | for_statement
    | match_statement
    | jump_statement

  expression_statement
    : expression ';'

  if_statement
    : IF expression block
    | IF expression block ELSE statement

  while_statement
    : WHILE expression block

  for_statement
    : FOR IDENTIFIER IN expression block

  match_statement
    : MATCH expression '{' match_arms '}'

  match_arms
    : match_arms match_arm
    | match_arm

  match_arm
    : CASE pattern guard ARROW statement
    | DEFAULT ARROW statement

  guard
    : IF expression
    |

  pattern
    : literal
    | IDENTIFIER
    | IDENTIFIER '(' optional_patterns ')'
    | '[' optional_patterns ']'

  optional_patterns
    : patterns
    |

  patterns
    : pattern
    | patterns ',' pattern

  jump_statement
    : BREAK ';'
    | CONTINUE ';'
    | RETURN optional_expression ';'

  optional_expression
    : expression
    |

  expression
    : assignment

  assignment
    : conditional
    | postfix '=' assignment

  conditional
    : logical_or
    | IF logical_or ELSE conditional

  logical_or
    : logical_or OR logical_and
    | logical_and

  logical_and
    : logical_and AND equality
    | equality

  equality
    : equality EQ comparison
    | equality NE comparison
    | comparison

  comparison
    : comparison '<' additive
    | comparison '>' additive
    | comparison LE additive
    | comparison GE additive
    | additive

  additive
    : additive '+' multiplicative
    | additive '-' multiplicative
    | multiplicative

  multiplicative
    : multiplicative '*' unary
    | multiplicative '/' unary
    | multiplicative '%' unary
    | unary

  unary
    : '!' unary
    | '-' unary = UMINUS
    | postfix

  postfix
    : primary
    | postfix '(' optional_arguments ')'
    | postfix '[' expression ']'
    | postfix '.' IDENTIFIER

  optional_arguments
    : arguments
    |

  arguments
    : expression
    | arguments ',' expression

  primary
    : literal
    | IDENTIFIER
    | '(' expression ')'
    | array_literal

  literal
    : NUMBER
    | STRING
    | TRUE
    | FALSE
    | NULL

  array_literal
    : '[' optional_arguments ']'

  identifier_list
    : IDENTIFIER
    | identifier_list ',' IDENTIFIER
end
---- header
require "strscan"
---- inner
KEYWORDS = {
  "import" => :IMPORT, "from" => :FROM, "as" => :AS,
  "type" => :TYPE, "enum" => :ENUM, "fn" => :FN,
  "let" => :LET, "const" => :CONST, "if" => :IF, "else" => :ELSE,
  "while" => :WHILE, "for" => :FOR, "in" => :IN,
  "break" => :BREAK, "continue" => :CONTINUE, "return" => :RETURN,
  "match" => :MATCH, "case" => :CASE, "default" => :DEFAULT,
  "true" => :TRUE, "false" => :FALSE, "null" => :NULL
}.freeze

OPERATORS = {
  "||" => :OR, "&&" => :AND, "==" => :EQ, "!=" => :NE,
  "<=" => :LE, ">=" => :GE, "->" => :ARROW
}.freeze

def parse(source)
  @scanner = StringScanner.new(source)
  do_parse
end

def next_token
  loop do
    @scanner.skip(/\s+/)
    @scanner.skip(%r{//[^\n]*(?:\n|\z)})
    break unless @scanner.matched?
  end
  return false if @scanner.eos?

  if (string = @scanner.scan(/"(?:\\.|[^"\\])*"/))
    [:STRING, string]
  elsif (number = @scanner.scan(/\d+(?:\.\d+)?/))
    [:NUMBER, number]
  elsif (identifier = @scanner.scan(/[A-Za-z_][A-Za-z0-9_]*/))
    [KEYWORDS.fetch(identifier, :IDENTIFIER), identifier]
  elsif (operator = @scanner.scan(/\|\||&&|==|!=|<=|>=|->/))
    [OPERATORS.fetch(operator), nil]
  elsif (punctuation = @scanner.scan(/[{}()\[\],;:.=<>+\-*\/%!]/))
    [punctuation, nil]
  else
    raise ArgumentError, "unexpected benchmark input at offset #{@scanner.pos}"
  end
end
