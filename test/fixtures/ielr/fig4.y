class Ibex::Test::Fig4
rule
  s : 'a' x 'a' | 'a' x 'b' | 'a' y 'a'
    | 'b' x 'a' | 'b' y 'b'
  x : 'a'
  y : 'a'
end
