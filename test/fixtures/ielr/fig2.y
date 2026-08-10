class Ibex::Test::Fig2
rule
  s : 'a' x 'a' | 'a' y 'b' | 'a' z 'c'
    | 'b' x 'b' | 'b' y 'a' | 'b' z 'a'
  x : 'a' 'a'
  y : 'a' 'a'
  z : 'a' 'a'
end
