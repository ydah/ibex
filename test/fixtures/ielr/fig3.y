class Ibex::Test::Fig3
rule
  s : 'a' x 'a' | 'a' y 'a' | 'a' z 'a'
    | 'b' x 'b' | 'b' y 'a' | 'b' z 'a'
  x : 'a' 'a'
  y : 'a' 'a'
  z : 'a' 'a'
end
