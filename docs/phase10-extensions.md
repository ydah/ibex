# Phase 10 extensions

## E3: conflict witnesses

`Ibex::LALR::Counterexample` accepts only Automaton IR. It explores parser-stack configurations, forces each pair of competing
actions at the requested conflict, and then searches for a common suffix that lets both branches accept the same terminal
sentence. A successful result contains `unifying: true`, the conflict lookahead position, and both complete derivation trees.

Because unifying-counterexample search is not guaranteed to terminate for every context-free grammar, the search has explicit
token and configuration budgets. If no common sentence is found within those budgets, the result is marked `unifying: false`
and contains the deterministic shortest reachability witness. This distinction prevents a nonunifying diagnostic from being
presented as proof of ambiguity.

## E7: Ruby DSL

`Ibex::Frontend::DSL.grammar` constructs the existing AST with synthetic locations and joins the normal pipeline at Normalizer.
Text and DSL inputs therefore share symbol classification, EBNF expansion, validation, algorithms, and outputs.

## E9: construction algorithms

The builder first constructs canonical LR(1). `lr1` retains the states, `lalr` merges equal LR(0) cores, and `slr` applies FOLLOW
sets to completed items in the LR(0) states. All strategies use the same conflict resolver and Automaton IR.
