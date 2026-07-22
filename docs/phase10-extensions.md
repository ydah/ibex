# Phase 10 extensions

## E3: conflict witnesses

`Ibex::LALR::Counterexample` accepts only Automaton IR. It breadth-first searches transitions from state 0, expands nonterminal
edges to their fixed-point shortest terminal yields, appends the conflict lookahead, and reports both competing actions. Reduce
interpretations contain one-step derivation trees. These are deterministic reachability witnesses, not guaranteed fully unifying
counterexamples.

## E7: Ruby DSL

`Ibex::Frontend::DSL.grammar` constructs the existing AST with synthetic locations and joins the normal pipeline at Normalizer.
Text and DSL inputs therefore share symbol classification, EBNF expansion, validation, algorithms, and outputs.

## E9: construction algorithms

The builder first constructs canonical LR(1). `lr1` retains the states, `lalr` merges equal LR(0) cores, and `slr` applies FOLLOW
sets to completed items in the LR(0) states. All strategies use the same conflict resolver and Automaton IR.
