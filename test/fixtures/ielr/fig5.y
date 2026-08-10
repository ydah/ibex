class Ibex::Test::Fig5
preclow
  left 'a'
  left PREC_EMPTY_E
prechigh
rule
  s : 'a' x y 'a'
    | 'b' x y 'b'
  x : 'a' z d e
  y : 'c'
    |
  z : d
  d : 'a'
  e : 'a'
    | = PREC_EMPTY_E
end
