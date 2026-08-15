# Preview and Experimental maturity audit

[`maturity.yml`](maturity.yml) and the validator-owned commit authorities in
[`maturity_authority.rb`](../tool/quality/maturity_authority.rb) form the joint
human-reviewed trust boundary for H001. The registry binds the current 19
Preview and two Experimental features to the reviewed repository revision,
source digests, activation, external-use status, specification-history
confidence, issue audit, documentation and tooling gaps, performance and safety
limits, decision, next trigger, and release gates. Neither file authenticates
the other; changing a classification requires reviewing and updating both.

## Result

<!-- maturity-summary:start -->
Inventory: **19 Preview, 2 Experimental**. Active new Preview tracks: **2/3** (grammar syntax: **1/1**). Experimental product features: **2/5**.
Release dependency state: R001 **hold_external**; R002 **pending_exact_revision**; no feature is promoted by this audit.

| Stable ID | Feature | Current maturity | Decision | External use | Release gate |
| --- | --- | --- | --- | --- | --- |
| `ebnf-groups` | EBNF groups | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `parameterized-rules` | parameterized rules | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `inline-rules` | inline rules | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `middle-actions` | middle actions | Preview | Redesign Preview | not demonstrated | Blocked: R001, R002 |
| `multiple-entries` | multiple entries | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `canonical-imports` | canonical imports | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `generated-lexers` | generated lexers | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `semantic-locations-types` | semantic locations/types | Preview | Redesign Preview | not demonstrated | Blocked: R001, R002 |
| `ast-generation` | AST generation | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `grammar-tests` | grammar tests | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `documentation-tooling` | documentation tooling | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
| `impact` | Grammar impact analysis | Preview | Keep Preview | not demonstrated | Blocked: R001, R002 |
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

Every keep decision names unmet promotion evidence. Two rows record redesigns.
Compatible/default Racc middle actions are already governed by the Stable
compatibility contract, and no separable Preview activation currently exists;
the redundant Preview classification must be split or removed at the next
reviewed release unless a distinct opt-in extension is defined. Compatible-mode
location APIs and extended-only type declarations also require separate
inventory records and promotion gates. Passing repository tests is necessary,
but cannot establish external field compatibility, complete R001's independent
review, or replace R002 on the exact release revision.

Activation and maturity are independent. Middle actions are accepted in
compatible/default grammars when an action is embedded before the end of a
production, so the Stable guarantee takes precedence over Preview notice.
Compatible semantic actions can consume lexer locations; only grammar `type`
declarations require extended mode. Preview therefore does not imply that every
audited surface is disabled by default or may break under Preview policy.

The active declarative-parser-construction track changes how the already
Preview IELR and multiple-entry contracts can be activated: an extended root
grammar may now own those settings. It consumes the grammar-syntax budget but
does not add or promote a maturity-inventory row. Its source history and field
experience must be incorporated into the next reviewed maturity audit.

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

Each feature records its validator-owned first Git pickaxe introduction, first
containing release, canonical-blob presence, and integrity snapshots at v0.1.0,
v0.2.0, and the exact reviewed revision. Each release boundary separately
records one assessment for every path-relevant commit. An assessment binds the
full revision, exact Git subject, classification, and commit-specific public
contract effect. The validator reconstructs the reviewed commits from Git,
checks ancestry and changed-path relevance, and derives both the boundary's
reviewed and semantic commit sets from those exhaustive assessments. The
path match determines which commits require assessment, not whether they are
semantic. `semantic_change` is reserved for an observable syntax, API, output,
or runtime change when that inventory row's feature configuration is active;
changes behind mutually exclusive guards or confined to adjacent features are
classified as nonsemantic and name the relevant guard or code path. The
remaining `unknowns` state what repository history cannot establish, such as
downstream compatibility and field use; source age or a digest change alone
receives no semantic or promotion credit.

The introduction method is exactly
`git log --reverse --format=%H -SQUERY REVIEWED_REVISION -- PATH`; the reviewed
revision bound prevents later history from rewriting the audit result.
Boundary review uses `git log --reverse --format=%H FROM..TO -- PATH...` over
the validator-owned introduction and canonical paths. The first range starts at
the introduction commit's parent so the introduction itself is reviewed through
its first containing release; subsequent ranges join exact release and reviewed
revisions. Each source-tree digest hashes sorted canonical paths as path, NUL,
exact Git blob bytes (or the literal `<absent>`), NUL. Digests are integrity
evidence only: they neither discover nor classify semantic changes. Tags
resolve to full commit IDs, and introductions, releases, and reviewed commits
must have the recorded ancestry and order.

## Updating the audit

Run:

```sh
bundle exec rake quality:maturity
bundle exec ruby -Itest test/quality/maturity_test.rb
```

For history changes, update the exhaustive assessments in `maturity.yml` and
the explicit per-feature/per-boundary semantic authority together after human
review. Update source SHA-256 values only as integrity records; never use them
to infer semantics. A promotion also requires the feature's next-review
evidence, completed R001 and exact-revision R002 states, and a synchronized
generated summary in this file and [`stability.md`](stability.md). A redesign
or removal is visible in the same summary and still follows the applicable
Preview or Experimental compatibility policy.
