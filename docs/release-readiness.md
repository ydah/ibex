# v1.0 readiness report

This is the outcome-based v1.0 decision required by the project design. It
records measurements taken on 2026-07-26 with Ruby 4.0.0 on
`arm64-darwin24`. Passing the implementation checklist is not sufficient for a
stable release.

## Decision

**HOLD v1.0.** Compatibility behavior, scale construction, semantic-value
signatures, and the repository compatibility suite have evidence. The external
generator/runtime performance target is not met, and the published ten-case
error comparison has not received independent third-party review.

The feature freeze remains in force while those two release gates are open.
Preview and experimental features may continue to ship in prereleases without
being promoted.

## KPI result

| KPI | Result | Evidence |
|---|---|---|
| Three public-gem migrations | Pass with documented adapters | Namae, BCDice, and Nokogiri behavior suites below |
| Hundreds-of-productions scale | Pass | 501 productions, 503 states, 125.008 ms average complete build |
| Ten-case error UX comparison | Partial | 10/10 snapshots and 8/10 useful repairs are public; independent review is missing |
| Generator and parser performance at least racc | Fail | Every measured external generator and parser loop is slower; the current internal artifact also regresses |
| Semantic-value RBS and typed ratchet | Pass | Generated reduction signatures include declared RHS/LHS types; whole-library Steep is 88.2% typed |
| Compatibility suite unbeaten | Pass at the measured revision | Current black-box, self-host, IR, property, and runtime suites are green |

## Public-gem migration evidence

Only public grammar files, public commands, and observable test results were
used. Neither racc implementation files nor generated source were inspected.
Each repository was cloned at the recorded revision:

| Project | Revision and grammar | Static check | Behavior result |
|---|---|---|---|
| Namae | [`d33875a`](https://github.com/berkmancenter/namae/commit/d33875aaf1fc420a8dfe946a3b29cc3e19710061), `lib/namae/parser.y` | compatible | 151 RSpec examples, 85 Cucumber scenarios, 198 steps |
| BCDice | [`21b4a03`](https://github.com/bcdice/BCDice/commit/21b4a03789bf2080ad41aaf31299b609ee7bda86), `lib/bcdice/command/parser.y` | compatible; runtime-constant warning | 25 tests, 103 assertions |
| Nokogiri | [`04a4c29`](https://github.com/sparklemotion/nokogiri/commit/04a4c29c6a605ad40a78f4ce343ced0832a1805c), `lib/nokogiri/css/parser.y` | compatible; runtime-constant warning | 6 tests, 14 assertions |

Namae generated and ran as one embedded file. The other two grammars contain a
user header whose superclass is named `Racc::Parser`. Their PoCs preload this
explicit migration adapter before loading the generated parser:

```ruby
require "ibex/runtime"

module Racc
  Parser = Ibex::Runtime::Parser
end
```

This is the adapter recommended by `ibex migrate-check`; it does not load or
execute the racc runtime. The PoCs uncovered and fixed three compatibility
gaps: an omitted `end` before a user-code section, an application initializer
that omits `super` plus historical value-stack reads, and an unqualified
`ParseError`. See ADRs
[0071](decisions/0071-legacy-user-code-rule-termination.md),
[0072](decisions/0072-lazy-runtime-session-compatibility.md), and
[0073](decisions/0073-parser-parse-error-alias.md).

## External performance comparison

Generator rows are one cold command observation. Runtime rows use one parser,
2,000 warm-up parses, then 20,000 timed parses. Times are wall-clock seconds on
the same host and checkout. They are evidence for the release decision, not
portable scores.

| Project | Generator racc | Generator Ibex | Ratio | Runtime racc | Runtime Ibex | Ratio |
|---|---:|---:|---:|---:|---:|---:|
| Namae | 0.29 s | 0.42 s | 1.45x slower | 0.316441 s | 0.776317 s | 2.45x slower |
| BCDice | 0.23 s | 0.42 s | 1.83x slower | 0.175542 s | 1.477350 s | 8.42x slower |
| Nokogiri CSS | 0.22 s | 0.63 s | 2.86x slower | 0.423988 s | 2.004314 s | 4.73x slower |

The current realistic in-repository artifact has 139 productions, 250
direct-LALR construction/final states, 60.328 ms generation, and 2.028/2.251
ms plain/compact parser observations. Against the preceding artifact on the
same Ruby/OS/CPU series, generation is 4.7% slower and runtime is 21.4%/20.4%
slower. Deterministic Grammar IR, Automaton IR, tables, runtime result, and
their digests are unchanged; generated output digests and sizes changed. This
is an internal performance regression as well as an external KPI failure.

## Scale evidence

Run:

```sh
benchmark/scale.rb --rules 500 --iterations 3
```

The reproducible synthetic chain shares its grammar shape with the 500-rule
black-box compatibility test. The measured report contains 501 productions,
503 direct-LALR construction states, 503 final states, no conflicts, and
41,332 bytes of compact generated Ruby. Three complete parse-to-codegen builds
averaged 125.008 ms with a 122.742–127.002 ms range. The Automaton IR digest
was `fe0e2f0c9bf16e7aa22a7ebcea40b229fedbb573f83af37596b76e0b989c3338`.

This synthetic result establishes the requested scale bound. The 139-production
representative grammar remains the realistic workload, so neither result is
presented as a substitute for an application-specific benchmark.

## Error UX and type evidence

[`error-ux.md`](error-ux.md) and its versioned JSON publish the same ten
malformed JSON inputs against the public racc callback. Eight selected repairs
were assessed useful. A maintainer assessment is not independent review; at
least one external reviewer must record a review of the cases and usefulness
labels before this KPI passes.

The current whole-library `steep stats` result is 16,836 typed calls and 2,258
untyped calls out of 19,094, or 88.2% typed. Generated parser RBS refines
declared terminal, nonterminal, RHS tuple, and reduction result types. Untyped
values remain explicit at undeclared grammar symbols, decoded JSON, dynamic
table cells, and opaque application Ruby boundaries.

## Actions required to release v1.0

1. Add representative external parser profiles, optimize the dominant runtime
   and generator costs, and repeat the same public-gem measurements until no
   row is slower than racc.
2. Obtain and link an independent review of the ten error cases and usefulness
   judgments; revise the versioned assessment if the review disagrees.
3. Re-run every compatibility, IR, type, benchmark, and site gate on the exact
   release revision.
