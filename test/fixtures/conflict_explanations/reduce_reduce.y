class H004ReduceReduce
pragma extended
token WORD
%expect-rr 1
rule
start: left
     | right
left: WORD
right: WORD
end
