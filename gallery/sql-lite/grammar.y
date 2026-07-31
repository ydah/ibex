class Gallery::SQLLiteParser
pragma extended
token SELECT FROM WHERE AND OR IDENTIFIER NUMBER STRING
preclow
  left OR
  left AND
prechigh
lexer
  skip /[[:space:]]+/
  SELECT /SELECT/i
  FROM /FROM/i
  WHERE /WHERE/i
  AND /AND/i
  OR /OR/i
  NUMBER /(?:0|[1-9][0-9]*)(?:\.[0-9]+)?/
  STRING /'(?:''|[^'])*'/
  IDENTIFIER /[A-Za-z_][A-Za-z0-9_]*/
  on /[,=*;]/ { |text| emit text, text }
end
rule
  document: statement ';' { result = val[0] }
  statement: SELECT columns FROM IDENTIFIER where_clause
  columns: '*' | identifiers
  identifiers: IDENTIFIER | identifiers ',' IDENTIFIER
  where_clause: | WHERE predicate
  predicate: predicate AND predicate
           | predicate OR predicate
           | IDENTIFIER '=' value
  value: NUMBER | STRING | IDENTIFIER
end
