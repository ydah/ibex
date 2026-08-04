# Preview and Experimental maturity audit

[`maturity.yml`](maturity.yml) is the machine-readable authority for the H001
review. It binds the current 18 Preview and two Experimental features to the
reviewed repository revision, source digests, activation, external-use status,
specification-history confidence, issue audit, documentation and tooling gaps,
performance and safety limits, decision, next trigger, and release gates.

## Result

<!-- maturity-summary:start -->
Inventory: **18 Preview, 2 Experimental**. Active new Preview tracks: **0/3** (grammar syntax: **0/1**). Experimental product features: **2/5**.
Release dependency state: R001 **hold_external**; R002 **pending_exact_revision**; no feature is promoted by this audit.

| Stable ID | Feature | Current maturity | Decision | External use | Release gate |
| --- | --- | --- | --- | --- | --- |
| `ebnf-groups` | EBNF groups | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `parameterized-rules` | parameterized rules | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `inline-rules` | inline rules | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `middle-actions` | middle actions | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `multiple-entries` | multiple entries | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `canonical-imports` | canonical imports | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `generated-lexers` | generated lexers | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `semantic-locations-types` | semantic locations/types | Preview | Redesign Preview | not demonstrated | Blocked: R001, R002 |
| `ast-generation` | AST generation | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `grammar-tests` | grammar tests | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `documentation-tooling` | documentation tooling | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `ielr` | IELR | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `lsp` | LSP | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `watch` | watch | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `debug` | debug | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `coverage` | coverage | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `browser-playground` | browser playground | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `action-shadow` | action-shadow | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `bounded-repair` | bounded repair | Experimental | Keep Experimental | not demonstrated | Blocked: R001, R002 |
| `incremental-cst` | incremental CST | Experimental | Keep Experimental | not demonstrated | Blocked: R001, R002 |
<!-- maturity-summary:end -->

Every keep decision names unmet promotion evidence. The semantic
locations/types row instead records a redesign: compatible-mode location APIs
and extended-only type declarations require separate inventory records and
promotion gates. Passing repository tests is necessary, but cannot establish
external field compatibility, complete R001's independent review, or replace
R002 on the exact release revision.

Activation and maturity are independent. In particular, middle actions are
accepted in compatible/default grammars when an action is embedded before the
end of a production. Compatible semantic actions can consume lexer locations;
only grammar `type` declarations require extended mode. Preview therefore does
not imply that every audited surface is disabled by default.

## Evidence boundaries

External use is evaluated against the stable IDs and classifications in the
[public workload registry](workloads.md). `repository_synthetic` gallery use
supports correctness testing only. `external_real` Bison inputs support only
their registered diagnostic scope. Neither class is reported as third-party
Ibex adoption. The current `public_real` records exercise compatible-mode
generation and runtime, not one of the audited Preview or Experimental
features, so every external-use result is `not_demonstrated`.

The issue audit ran the exact GitHub Search API query and command recorded in
the YAML on 2026-08-04. It returned zero open issues with a complete result.
That result expires after 30 days and means only that the public tracker had no
open report matching the query; it is not a correctness proof. The validator
fails after the recorded freshness deadline until the exact audit is rerun and
reviewed.

Each feature records its first Git pickaxe introduction, first containing
release, and digest-bound canonical source snapshots at v0.1.0, v0.2.0, and
the reviewed pre-H001 revision. The remaining `unknowns` state what this
repository history cannot establish, such as downstream compatibility and
field use; source age alone receives no promotion credit.

The introduction method is exactly
`git log --reverse --format=%H -SQUERY -- PATH`. Each source-tree digest hashes
the feature's validator-owned canonical paths in sorted order as path, NUL,
exact Git blob bytes (or the literal `<absent>`), NUL. Tags are resolved to the
full commit IDs in the registry, and every introduction must be an ancestor of
the fixed reviewed authority `96db239bb6b40723cce94f42d8d4262ba3477fec`.

## Updating the audit

Run:

```sh
bundle exec rake quality:maturity
bundle exec ruby -Itest test/quality/maturity_test.rb
```

Update source SHA-256 values only after reviewing the semantic change. A
promotion also requires the feature's next-review evidence, completed R001 and
exact-revision R002 states, and a synchronized generated summary in this file
and [`stability.md`](stability.md). A redesign or removal is visible in the same
summary and still follows the applicable Preview or Experimental compatibility
policy.
