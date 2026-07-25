class Parameterized::Parser
pragma extended
token NUM COMMA
type list "Array[untyped]"
rule
list(X): X:value { result = [value] }
       | list(X) COMMA X { result = val[0] + [val[2]] }
wrapped(X): (X | list(X))?
start: wrapped(list(NUM)):items { result = items }
end
