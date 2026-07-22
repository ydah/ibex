class Demo::Parser < BaseParser
token INT PLUS ','
prechigh
  right UMINUS
  left PLUS
preclow
options no_result_var omit_action_call
expect 1
start program
convert
  INT 'IntegerToken'
  PLUS ':plus'
end
rule
  program : expressions { result = val[0] }
  expressions : expression
              | expressions PLUS expression { result = val[0] + [val[2]] }
  expression : INT = UMINUS
             |
end
---- header
require "json"
---- inner
def helper = 1
---- footer
Demo::Parser.new
