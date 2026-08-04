# Public workload and problem registry

[`workloads.yml`](workloads.yml) is the machine-readable authority for workload
identity, source and license evidence, structural measurements, known problems,
workarounds, and benchmark eligibility. It is a planning registry, not a claim
that every grammar is fully supported or that every eligible scope has a
published result.

## Source classes

The `classification` field prevents unlike evidence from being combined:

| Class | Meaning |
| --- | --- |
| `public_real` | A public third-party application grammar with an exact repository revision. |
| `external_real` | A public third-party grammar used by the download-only Bison import gate. |
| `repository_real` | A production Ibex workload, currently the self-hosted frontend. |
| `repository_synthetic` | A repository-authored correctness fixture; it is not adoption or public-language evidence. |

In particular, the gallery is `repository_synthetic`. Its results can support
correctness, fuzzing, and verifier claims, but cannot by themselves establish a
benefit for Namae, BCDice, Nokogiri, CRuby, jq, PHP, or PostgreSQL. The three
`public_real` workloads may support only the scopes listed in their eligibility
records and only after the benchmark's checkout and behavior checks pass.

## Counting contract

`ibex-normalized-lalr-v1` parses the exact pinned bytes in their admitted mode,
normalizes them to Grammar IR, counts user productions and all normalized
terminals (including `$eof` and `error`), then builds the direct LALR automaton
and counts states and unresolved conflicts. Bison-family sources are first
processed by the Ibex importer, which strips actions and reports unsupported
directives.

`measured` means that the complete grammar admitted by that method was counted.
`not_measured` requires a reason and carries no numeric value. The pinned current
CRuby Lrama grammar has 22 structural import gaps, so its partial importer
figures are deliberately not promoted to production, token, state, or conflict
counts.

The registry validator recomputes repository-owned grammar counts, cross-checks
the three public identities and grammar digests against
[`benchmark/public_workloads.json`](../benchmark/public_workloads.json), and
cross-checks Bison identities and structurally complete expected metrics against
[`tool/quality/bison_external.rb`](../tool/quality/bison_external.rb). It does
not download third-party source in ordinary CI.

## Registered workloads

Counts are production/state/token. `n/m` means `not_measured`, not zero.

| Stable workload ID | Class | Grammar | Counts | Conflicts SR/RR | Benchmark status and scope |
| --- | --- | --- | ---: | ---: | --- |
| `bcdice-command-parser` | `public_real` | BCDice command parser | 34/56/19 | 2/0 | eligible: public generation/runtime |
| `bison-gnu-calc` | `external_real` | GNU Bison C calculator | 13/22/11 | 0/0 | diagnostic only: Bison import compatibility |
| `bison-jq-parser` | `external_real` | jq parser | 167/311/100 | 408/0 | diagnostic only: import/conflict analysis |
| `bison-php-parser` | `external_real` | PHP Zend language parser | 635/1203/185 | 0/0 | diagnostic only: import/scale construction |
| `bison-postgresql-parser` | `external_real` | PostgreSQL backend SQL grammar | 3640/6942/562 | 0/0 | diagnostic only: import/scale construction |
| `bison-ruby-bison-era` | `external_real` | CRuby Bison-era parse.y | 781/1303/158 | 0/0 | diagnostic only: import/external state comparison |
| `bison-ruby-current-lrama` | `external_real` | Pinned current CRuby Lrama parse.y | n/m | n/m | ineligible: structurally incomplete import |
| `gallery-calc` | `repository_synthetic` | Calculator fixture | 7/15/9 | 0/0 | eligible: correctness/fuzzing/verification |
| `gallery-json` | `repository_synthetic` | JSON fixture | 17/27/13 | 0/0 | eligible: correctness/fuzzing/verification |
| `gallery-sql-lite` | `repository_synthetic` | SQL-subset fixture | 14/26/14 | 0/0 | eligible: correctness/fuzzing/verification |
| `ibex-frontend` | `repository_real` | Production self-hosted grammar | 141/220/59 | 0/0 | eligible: self-host/regression |
| `namae-parser` | `public_real` | Namae name parser | 51/78/12 | 0/0 | eligible: public generation/runtime |
| `nokogiri-css-parser` | `public_real` | Nokogiri CSS parser | 81/117/32 | 0/1 | eligible: public generation/runtime |

The exact owner/project, full revision, path, source SHA-256, license expression
and evidence digest, public-source permission evidence, feature inventory,
current pain, current workaround, and eligibility reasons live in the YAML
record. Third-party license locators include the full pinned revision; their
digests were calculated from those exact bytes. The registry records evidence
and does not replace a project's license terms or legal review.

## Stable problem IDs

Future design and profiling work should cite a problem and at least one workload
ID instead of saying only that a change helps “real grammars.”

| Stable problem ID | Current evidence boundary |
| --- | --- |
| `problem-bison-dialect-coverage` | Every pinned Bison-family import reports at least one unsupported directive; current CRuby has structural gaps. |
| `problem-conflict-volume` | `bison-jq-parser` has 408 unresolved shift/reduce conflicts in the measured imported direct-LALR automaton. This is not a claim about jq's production parser behavior. |
| `problem-public-runtime-performance` | The evidence-pending historical projection retains slower cold-generation and new-instance rows for the three `public_real` workloads. |

For example, a direct-IELR proposal can cite
`problem-conflict-volume` + `bison-jq-parser`, but it must still establish that
the imported conflicts are semantically meaningful before claiming an
application benefit. A runtime optimization can cite
`problem-public-runtime-performance` plus the affected public workload IDs and
must publish a new environment-bound comparison artifact before making a
current performance claim.

## Updating the registry

Run:

```sh
bundle exec rake quality:workloads
bundle exec ruby -Itest test/quality/workloads_test.rb
```

For a repository grammar, update its revision to a commit that already contains
the recorded source bytes, update its digest, and let the validator recompute
counts. The initial repository entries intentionally use pre-registry revision
`2bb20ab24e26cae4ee7cd397fcc12938b7d24e59`, avoiding a self-referential
registry commit.

For a public benchmark grammar, change
`benchmark/public_workloads.json` and this registry together. For a Bison input,
change the source constant, digest, expected measurements, exact-revision
license evidence, and registry together. A moving branch, tag without a
resolved commit, short SHA, missing/changed local file, digest mismatch,
unexplained numeric placeholder, or eligible record without complete count,
license, and permission evidence fails the quality gate.
