class ExtendedParser
token A B C D ITEM
rule
  values : (A (B | C)?)+ ITEM:first separated_list(D, ',')
end
