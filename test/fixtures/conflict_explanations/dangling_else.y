class H004DanglingElse
pragma extended
token IF THEN ELSE ID
expect 1
rule
statement: IF expression THEN statement
         | IF expression THEN statement ELSE statement
         | ID
expression: ID
end
