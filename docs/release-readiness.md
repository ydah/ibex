# v1.0 readiness report

This is the outcome-based v1.0 decision required by the project design. It
records evidence current through 2026-07-31. Performance measurements used
Ruby 4.0.0 on `arm64-darwin24`. Passing the implementation checklist is not
sufficient for a stable release.

## Decision

**HOLD v1.0.** Compatibility behavior, scale construction, semantic-value
signatures, and the repository compatibility suite have evidence. A historical
public performance projection is documented, but its direct formal result
artifact is absent. The published ten-case error comparison has not received
independent third-party review. Its machine-readable
[`R001` status](error-ux-review-status-v1.json) is
`HOLD / awaiting_independent_review`; the linked status leads to the complete
rubric, closed record schema, immutable evidence identity, and imported-record
registry.

<!-- r001-review-status:start -->
R001: `HOLD` — [`awaiting_independent_review`](error-ux-review-status-v1.json).
<!-- r001-review-status:end -->

Feature development is not frozen. The open release gate blocks publication of
v1.0, not feature development. New work remains subject to the feature budgets,
maturity rules, compatibility checks, and exact-revision release gates
documented by the project. The versioned core Grammar IR and Automaton IR
contracts remain frozen.

The format-v6 batch Red/Green CST has been selected as part of the initial
Stable v1 API. Its syntax-only incremental layer remains Experimental. Other Preview and
Experimental features may continue to ship in prereleases without promotion.

## KPI result

| KPI | Result | Evidence |
|---|---|---|
| Three public-gem migrations | Pass with documented adapters | Namae, BCDice, and Nokogiri behavior suites below |
| Hundreds-of-productions scale | Pass | 501 productions, 503 states, 125.008 ms average complete build |
| Ten-case error UX comparison | Partial | 10/10 snapshots and 8/10 useful repairs are public; independent review is missing |
| Public generator/runtime performance baseline | Partial | A fixed-revision reviewed projection is published below, but the direct formal result artifact is absent |
| Semantic-value RBS and typed ratchet | Pass | Generated reduction signatures include declared RHS/LHS types; whole-library Steep is 88.9% typed |
| Compatibility suite unbeaten | Pass at the measured revision | Current black-box, self-host, IR, property, and runtime suites are green |
| Release basis | Pass without publication | Stable declaration diff is 0 across 48 locked files; both gems build byte-identically under two environments |

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
`ParseError`.

## Formal Pure Ruby performance comparison

<!-- comparative-evidence:racc-public-performance-2026-07-31:start -->
At clean Ibex revision 08c7dc5d939a1f47b0132ae3986818cdbaec1f34, the readiness
projection for three pinned workloads on Ruby 4.0.0, arm64-darwin24, with YJIT disabled
records slower cold generation and new-instance runtime than Racc 1.8.1's Ruby backend;
the direct formal result artifact is absent, so this is evidence-pending and non-publishable
as a comparative claim.

Evidence record ID: `racc-public-performance-2026-07-31`. Its complete scope,
evidence paths, missing artifact, and limitations are registered in
[`claims.yml`](claims.yml) under the [comparison policy](comparison-policy.md).
CPU model, kernel release, and processor count were not retained in this
readiness projection. Host CPU and host OS were also not recorded as separate
fields. The measurements below do not describe the current checkout.

The historical readiness projection says the measurement was collected on
2026-07-31 from clean revision
`08c7dc5d939a1f47b0132ae3986818cdbaec1f34` with ten
alternating isolated runs per implementation, 50 warm-up workloads, 250
measured workloads, and 10,000 bootstrap samples. Each workload parses the
five fixed public inputs. Ruby 4.0.0 ran with YJIT disabled; Racc 1.8.1 was
forced to its Ruby backend and every worker verified the selected runtime.
Ratios below are Ibex divided by Racc; time cells include the bootstrap 95%
interval. The harness's `target_met` field marks absolute parity when the
interval's upper bound is no greater than 1.0. That field is diagnostic:
v1.0 requires publication of measurements and their conditions, while a
future performance gate may reject only a relative regression measured under
an identical environment and configuration.

| Project | Cold generation time | Reuse time | Reuse allocations | New-instance time | New-instance allocations | Generated bytes |
|---|---:|---:|---:|---:|---:|---:|
| Namae | 1.238x [1.184, 1.272] | 0.985x [0.966, 1.032] | 0.849x | 1.194x [1.157, 1.248] | 1.190x | 0.862x |
| BCDice command | 1.329x [1.278, 1.420] | 1.052x [1.008, 1.075] | 0.666x | 1.373x [1.326, 1.415] | 1.103x | 0.981x |
| Nokogiri CSS | 1.309x [1.277, 1.343] | 0.985x [0.963, 1.029] | 0.662x | 1.186x [1.149, 1.255] | 1.051x | 0.937x |

Result values and ordered result sequences are equivalent in every runtime
row. The measured parser-time medians in milliseconds per parse were
0.039443/0.040048 (Ibex/Racc) for Namae reuse,
0.020925/0.019897 for BCDice reuse, and
0.024892/0.025280 for Nokogiri reuse. The corresponding new-instance medians
were 0.048234/0.040413, 0.027523/0.020044, and 0.030420/0.025642.

The results deliberately retain the unfavorable rows: cold generation is
23.8–32.9% slower, and new-instance parsing is 18.6–37.3% slower. Reuse point
estimates range from 1.5% faster to 5.2% slower. Ibex allocates fewer objects
for every reuse workload, while new-instance allocation ratios remain
1.051–1.190x. Generated output is smaller for all three grammars. These values
are a release baseline, not portable scores or an assertion of parity.
<!-- comparative-evidence:racc-public-performance-2026-07-31:end -->

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
labels before this KPI passes. Reviewers use the versioned
[`independent rubric`](error-ux-review-rubric-v1.md), generate a draft with the
exact checkout and environment identity, set all structured consent fields, and
publish the final permalink-free payload at a full-SHA blob URL. Maintainers
import the exact bytes and register publication provenance separately, without
rewriting. Ordinary CI validates the offline kit; the release gate performs
fail-closed blob checks and requires the source owner, GitHub API author,
publisher, and reviewer logins to agree. This establishes only GitHub namespace
control and account metadata, not cryptographic identity or a signature. The
gate remains intentionally failing while the public status is HOLD.

The current whole-library `steep stats` result is 23,517 typed calls and 2,946
untyped calls out of 26,463, or 88.9% typed. Generated parser RBS refines
declared terminal, nonterminal, RHS tuple, and reduction result types. Untyped
values remain explicit at undeclared grammar symbols, decoded JSON, dynamic
table cells, and opaque application Ruby boundaries.

## Release-basis evidence

`bundle exec rake release:reproducible` compares 48 normalized Stable RBS
declaration files with the v0.2.0 baseline. The current result has zero
differences; the installed-Gem embedded-source helper is an internal packaging
implementation and is outside that public lock. The task also builds both
gems twice under distinct locale, timezone, and frozen-string settings and
requires byte-identical artifacts. SHA-256 digests are emitted for the exact
candidate revision rather than recorded as if the current HOLD revision were
a release.

No release signing credential is stored in this repository. A signature or
provenance attestation must be supplied by a protected external release
environment after the outcome gates pass; an unsigned local test key would not
establish publisher identity.

## Actions required to release v1.0

1. Obtain and publish an independent review of the ten error cases using the
   R001 rubric, then import the record byte-for-byte with its immutable
   permalink and consent. Preserve disagreements separately from the normative
   maintainer assessment.
2. Publish the complete formal performance result artifact or rerun its
   registered command on the exact candidate revision; do not promote the
   readiness projection into a comparative claim by reconstruction.
3. Re-run every compatibility, IR, type, benchmark, and site gate on the exact
   release revision.
