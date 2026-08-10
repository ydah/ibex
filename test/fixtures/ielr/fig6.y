class Ibex::Test::Fig6
rule
  s : 'a' x 'a'
    | 'a' 'a' 'b'
    | 'b' x 'b'
  x : y z
  y : 'a'
  z : d
  d :
end
