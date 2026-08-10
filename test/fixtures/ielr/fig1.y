class Ibex::Test::Fig1
preclow
  left 'a'
prechigh
rule
  s : 'a' x 'a'
    | 'b' x 'b'
  x : 'a'
    | 'a' 'a'
end
