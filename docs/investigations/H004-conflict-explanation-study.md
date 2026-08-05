# H004 conflict-explanation usefulness study

## Problem evidence

Ibex can emit state/item explanations, bounded witnesses, and verified repair
proposals, but the repository currently tests those facilities separately. It
does not contain one fixed study corpus that lets a reviewer determine whether
the explanation identifies the cause of a conflict and whether a suggested
edit is useful. Consequently, the existence of a counterexample cannot be
promoted to a usefulness claim.

The first study will cover distinct conflict shapes rather than extrapolate
from the twenty-case expression-repair regression baseline. At minimum it will
include an ambiguous expression, dangling `else`, a reduce/reduce choice, and
an LR(1)-but-not-LALR merge conflict. Every grammar, explanation, search bound,
and proposed edit will be byte-bound in a deterministic machine artifact.

## Contract

The machine artifact records the fixed input identity, state/item context,
conflict alternatives, shortest or bounded witness classification, and any
machine-verified repair candidates. A separate review record asks a human to
identify the cause and choose an edit before seeing the repository's expected
classification. Reviewer answers remain subjective evidence; an empty review
registry is `HOLD`, never an inferred pass.

The study changes no parser-construction, conflict-resolution, generated-table,
or runtime contract. It does not claim that every conflict is ambiguous, that
every bounded witness is shortest without its stated bounds, or that a
machine-verified edit is the edit a maintainer should choose.

## Trust label

Grammar parsing, normalization, Automaton IR construction, conflict
explanation, the bounded counterexample search, and the existing repair
verifier are repository-trusted analysis code. Fixture grammar actions are
never executed. Human labels are external subjective evidence and are not
trusted merely because their JSON shape validates.

## Compatibility

The study consumes existing public analysis output and adds development-only
fixtures, a schema, a deterministic capture command, and quality gates. It
does not change CLI defaults or artifact formats. Existing `explain-v1` and
`fix-v3` documents remain authoritative for their own interfaces.

## Configuration admission

No grammar-owned or persistent configuration is admitted. Algorithm and search
bounds are fixed study inputs. Changing them requires a new evidence capture;
they are not silently inherited from a developer environment.

## ABI assessment

No public Ruby constant, method, generated table, native layout, RBS surface,
or serialized runtime ABI is added. The capture implementation is a repository
quality tool and its study schema describes evidence, not a runtime API.

## Bounds

Each case fixes positive token/configuration limits for explanation search and
the existing candidate, build, equivalence, and verifier limits for suggested
repairs. Explanation evidence records the typed outcome, explored count,
exhaustion flag, and both bounds. Exhaustion is explicitly `inconclusive` and
cannot be converted to a nonunifying witness, successful explanation, or safe
repair. Corpus-level ratios are descriptive for the fixed cases only.

## Oracle

The current independent Automaton IR verifier, bounded language/tree
equivalence checks, and a fresh rebuild of each applicable edit establish the
machine repair preconditions. They do not establish human usefulness. Review
records provide the latter observation and retain disagreement rather than
collapsing it into a maintainer-authored label.

## Tests

- deterministic regeneration and closed JSON Schema validation;
- exact grammar and artifact digests;
- coverage of shift/reduce, reduce/reduce, unifying, and nonunifying cases;
- explicit search and repair exhaustion outcomes;
- fresh rebuild and target-conflict removal for applicable edits;
- empty and malformed external review registry handling;
- package inclusion and documentation links.

## Claims

Before independent review, the only allowed claim is that the fixed corpus and
review kit are reproducible. No usefulness rate, comparative superiority, or
general conflict-repair success rate is publishable. A future summary must show
per-task answers and reviewer disagreement, not only an aggregate percentage.

## Kill conditions encountered

No kill condition has yet been encountered. The study will stop or narrow a
case if analysis executes user code, requires unbounded search, cannot bind its
input bytes, or presents a repair that has not passed the existing independent
verification and bounded equivalence gates. Missing external reviewers leaves
the subjective gate at `HOLD`; it does not block committing the reproducible
machine corpus.
