class Edge::Parser < BaseParser
token A B left end separated_list
rule
  first : A
  second :
         | B ;
  third : separated_list
  fourth : A:end
end
---- header
HEADER = true
---- header
ALSO_HEADER = true
