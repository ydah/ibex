# Generated lexer behavior and automaton decision

H006 profiles the generated lexer that exists today. It does not replace that
lexer, add an automaton implementation, or claim that the two lexical models
are interchangeable. The machine-readable authority is
[`lexer-profile-v1.json`](../tool/profile/evidence/lexer-profile-v1.json),
validated by
[`lexer-profile-v1.schema.json`](../schema/lexer-profile-v1.schema.json).

Run and verify the profile with:

```sh
bundle exec ruby tool/lexer_profile.rb \
  --output=tool/profile/evidence/lexer-profile-v1.json
bundle exec rake quality:lexer_profile
```

The profiler generates parsers from committed grammar sources and executes
their lexer and parser actions. It is therefore limited to trusted repository
sources. It never downloads or executes the registered third-party grammars.

## Semantics are different

The current `regexp` profile anchors one Ruby `Regexp` per declared rule. Ruby
chooses alternatives left-to-right inside that rule. Ibex then compares the
lexemes returned by every active rule, chooses the longest byte length, and
uses declaration order for a tie. These are two separate selection steps.

For example, `/a|ab/` returns `a` for input `ab` inside its one Ruby rule. A
regular-language automaton using maximal munch would select `ab`. Calling the
second result a faster implementation of the first would hide a tokenization
change.

The conditional `automaton` profile described by the design has maximal munch,
a declaration-order tie, declarative transitions, and bounded construction. It
also excludes arbitrary Ruby actions and unspecified parser-to-lexer feedback.
Those exclusions are a semantic boundary, not an implementation detail.

## Workloads and provenance

The evidence keeps source classes separate:

- `synthetic` contains all eight required adversarial fixtures plus the three
  registered gallery grammars. Every grammar and input has an exact Git
  revision, path, byte digest, and derivation. The chunk fixture expands its
  committed 128-byte seed 129 times, producing a 16,512-byte single token that
  crosses the 16KiB streaming boundary.
- `public_real` contains the exact BCDice, Namae, and Nokogiri CSS registry
  identities. They use external application lexers and have no verified Ibex
  generated-lexer port, so their status is `not_run`, their result is `null`,
  and they contribute no inferred measurements.

Synthetic success is not evidence that public-real lexers are suitable for an
automaton migration. Evidence is generated from a clean exact revision, and
that revision must be the first parent of the commit that records the evidence.
The capture identity covers that revision, clean/status provenance, the complete
bound execution-source closure, implementation subset, deterministic report
input, measurement policy, and heuristic policy. The verifier locates the same
identity in committed evidence history instead of accepting any ancestor with
rewritten derived fields. A shallow checkout that lacks the evidence commit's
parent or pinned fixture revisions fails closed; CI must fetch full history
rather than treating missing provenance as a match.

The capture command deliberately loads only the frontend, Grammar/Automaton IR,
normalizer, analysis/LALR construction, Ruby code generator, and generated
runtime graph. It does not load the public `ibex` aggregate, CLI, or configuration
graph. Every repository Ruby source reachable from that measurement graph is a
bound path, and capture aborts if another repository source is loaded. The public
schema and this document are explicit generator-gem packaging expectations.

## Measurements and limits

Each measured workload records states, rules per state, token byte lengths,
action-bearing rules, direct lexer/parser state mutation, parser feedback,
Regexp warnings, streaming peak buffer bytes, and incremental bytes read from
offset zero. Elapsed time and `GC.total_allocated_objects` deltas are retained
only as host-bound diagnostics. Both the schema and semantic validator require
`release_gate: false`; the quality comparison removes their values.

The alternation, lazy-quantifier, and direct `lexer_state =` inventories are
source-text heuristics over normalized rules and actions. They do not form a
complete Ruby or Regexp semantic analysis. Aliases, helper calls,
metaprogramming, indirect mutation, or dynamically composed behavior can be
missed. A zero count is not proof of absence.

The Unicode-property fixture uses String input. The current incremental
`SourceText` path stores binary bytes, so this profile does not claim that
Unicode-property matching works through that incremental path. The
parser-feedback fixture is semantically parsed successfully, but its
syntax-only incremental scan is `not_measured`: suppressing the parser action
also suppresses the state change needed before the next token.

Peak buffer bytes cover only `LexerInput`, not whole-process memory. The
incremental full-scan share covers generated-lexer bytes read after a committed
identity edit; it does not measure CST subtree reuse.

## Decision

| Scope | Decision | Reason |
| --- | --- | --- |
| Automatic replacement of the current Regexp lexer | **NO-GO** | `/a|ab/` proves different token boundaries; arbitrary actions and parser-driven state changes have no specified semantic translation. |
| A separately named automaton lexer profile | **MORE DATA** | All adversarial fixtures are measured, but there are zero verified public-real generated-lexer workloads, no standalone semantic contract, and no verified adoption trigger. |

Timing and allocation observations are not thresholds for either decision.
Reconsidering automatic replacement requires an explicit compatibility model,
an action/feedback contract, and differential evidence on verified real
generated lexers. Reconsidering the separate profile requires at least two such
public-real workloads, a bounded declarative semantics, and demonstrated user
pressure that the design addresses.
