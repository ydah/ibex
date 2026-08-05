class H004Expression
pragma extended
token NUM PLUS
expect 1
rule
start: expression
expression: expression PLUS expression
          | NUM
end
