---
title: Grammar impact analysis
description: Review grammar propagation with ibex impact.
---

# Grammar impact analysis

`ibex impact` is a Preview analysis surface for finding where a grammar change
can propagate. It works on Ibex's normalized Grammar and Automaton IR and does
not change parser generation or execute semantic actions.

## Two analysis modes

Use a symbol seed before editing a grammar:

```sh
ibex impact --symbol=expression parser.y
```

This is the potential-impact mode. It follows reference, FIRST, and FOLLOW
dependencies, reports shortest witnesses, and groups recursive symbols into
strongly connected components. It is intentionally conservative. A nullable
boundary is called out because a later nullable change can change the edge set
itself.

Use two inputs after editing:

```sh
ibex impact old-parser.y new-parser.y
```

This is the confirmed-impact mode. It compares nullable, FIRST, and FOLLOW
sets, grammar rules, actions' structured metadata, and symbol metadata such as
display labels, semantic types, and documentation, plus automaton states and
conflicts. Metadata-only changes are reported at Low severity. This mode is
the canonical input for CI review and `--fail-on`.

Reports are JSON by default and conform to
[`impact-v1.schema.json`](../schema/impact-v1.schema.json). `--format=text`
prints a compact summary. Symbols are sorted by name, states by ID, and
witnesses are deterministic for identical inputs.

## Useful gates

`--kind=reference,first,follow` limits potential propagation, while
`--depth=N` bounds it. `--severity=medium` is the default display threshold.
The accepted `--fail-on` values are `new_conflict`, `nullable_change`,
`first_change`, `follow_change`, `action_arity`, and `unreachable`.

`--baseline=PATH` records known conflict identities independently of numeric
state IDs. `--update-baseline` writes the current identities. A missing
baseline is treated as empty, so it is safe to introduce the option before a
baseline file exists.

## Coverage narrowing

Pass one coverage report per test when test-level selection is needed:

```sh
ibex impact --coverage=tmp/test-expression.json old-parser.y new-parser.y
```

Reports whose `grammar_digest` does not match the analyzed Automaton IR are
ignored and produce a warning. A merged report contains aggregate sessions and
cannot be decomposed back into individual tests; pass separate reports for
that use case.

## Performance evidence

Measure the three gallery grammars in an isolated process when reviewing
performance changes:

```sh
for grammar in gallery/*/grammar.y; do
  bundle exec ruby benchmark/impact.rb --grammar "$grammar" --iterations 3 --json
done
```

The benchmark reports `Sets` and graph construction time, allocated objects,
dependency-edge count, and the shallow storage size of the retained dependency
arrays. Ruby allocator and RSS measurements are process-level observations;
the dependency-edge count and storage size explain the intentional memory cost
of retaining impact dependencies.

## Limits and trust boundary

The analyzer treats action bodies and user code as opaque source. It uses only
`Action#named_refs` and `Action#context_length`, so position references such as
`$1` and `val[0]` are not inspected. A changed RHS with structured references
can produce a High finding, but source-only references remain a known blind
spot.

Potential mode cannot completely predict changes that cross a nullable
boundary; use two-version mode when the report warns about one. Impact is a
syntactic dependency analysis, not a semantic-equivalence proof and not a
replacement for `ibex equiv` or `ibex check`.

The feature is Preview. It is read-only, does not alter the default generation
path, and does not execute grammar actions or user-code sections.
