class H004LALRMerge
pragma extended
%expect-rr 2
rule
start: 'a' first 'd'
     | 'b' second 'd'
     | 'a' second 'e'
     | 'b' first 'e'
first: 'c'
second: 'c'
end
