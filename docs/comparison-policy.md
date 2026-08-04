# Comparative claim policy

This policy defines when Ibex documentation may compare Ibex with another
parser tool. The machine-readable registry is [`claims.yml`](claims.yml), and
`bundle exec rake quality:comparative_claims` validates the registry and its
public claim markers.

The initial comparison set is Racc, Lrama, GNU Bison, Menhir, Tree-sitter, and
ANTLR. A tool being in the set does not imply that a comparison has been made.
An unmeasured tool remains `not_compared`; unknown facts remain `unknown`.
Each entry also owns its canonical public aliases. README scanning recognizes
only this declared set and aliases; adding a tool or spelling requires a
reviewed registry change.

Tool-level state is derived from every registered claim that names that tool.
`pending_claims` is the canonical ordered list of claim IDs that are not yet
`measured`, and the reason is generated deterministically from those IDs,
their pending state, and their declared missing evidence. A tool with no claims
is `not_compared` with an empty pending list and unknown identity. A tool with
any pending claim is `evidence_pending`, even if another claim for that tool is
measured. `compared` is valid only when the tool has at least one claim, every
one is measured, and `pending_claims` is empty.

## Required record

Every measured, evidence-pending, or review-pending record contains:

- an immutable claim ID and narrowly scoped wording;
- each subject's exact released version and, when applicable, repository
  revision;
- one public command represented as an executable and an ordered argv list;
- fixed corpus paths and external revisions;
- known environment values and an explicit list of unrecorded values;
- excluded or unsupported semantics;
- the subjective review method and its completion state;
- repository-relative evidence paths and explicit limitations; and
- the SHA-256 of the canonical marker body, including every table and note; and
- an exact-revision validity scope, expiry statement, and conditions that
  require review.

Repository subjects and corpora use immutable 40- or 64-hex revisions. Released
tools use an exact release version and may use `not_applicable` only for the
repository revision. It must not conceal missing information. Every required
environment identity is either recorded as a non-placeholder value or listed
as `unknown`, and each unknown field is repeated in the public limitations.

No extra JSON Schema is used for this YAML registry. Its cross-file rules—file
existence, canonical ordering, public markers, and wording restrictions—need an
explicit repository validator and would not be made clearer by duplicating
them in a data-only schema.

## Public interface and corpus rules

Comparisons use public commands, public callbacks, or documented artifact
formats. Do not inspect another tool's implementation or generated source to
manufacture an advantage. If a public interface cannot expose a value, record
that limitation instead of inferring it.

Inputs, grammar revisions, lifecycle choices, lexer inclusion, runtime backend,
warm-up, repetitions, random seeds, and instrumentation must be fixed before a
measurement. Failure rows stay in the evidence. Results from different
environments or configurations form separate observations and must not be
silently merged.

## Subjective review

Diagnostic and repair usefulness are human judgments. The review method must
fix case IDs and the allowed labels, retain rationale and disagreements, and
separate maintainer assessment from independent assessment. A record whose
required independent review is missing stays `review_pending`; a record missing
its direct result artifact stays `evidence_pending`. Neither state can use a
public strong-claim marker or be worded as a completed comparative conclusion.

Performance statistics and deterministic behavior digests do not require a
subjective reviewer, but their scope and limitations still require ordinary
code review.

## Scoped wording

Comparative wording names the claim ID and states the relevant revision or
release, corpus, environment, measurement category, and important limitation.
For example:

> At revision X, on corpus Y and environment Z, metric M had the recorded
> relationship to tool version V. This does not describe other revisions,
> workloads, backends, or semantic capabilities.

Do not publish wording such as “faster than Racc” or “better diagnostics”
without those boundaries. README comparative strength wording is enclosed by
`comparative-claim` markers. Only a `measured` record with a direct result
artifact may use that marker. Pending material instead uses a
`comparative-evidence` marker around the full table or conclusion it records.
The validator requires each marker body to contain the registry wording exactly
and every registered table anchor. It also canonicalizes line endings and
trailing whitespace and requires the complete body SHA-256 to match, so any
other prose, table-cell, row, or blank-line change fails independently of its
vocabulary. It always scans README, even when no claim targets README, and
rejects unmarked paragraphs that combine a declared tool alias with English or
Japanese strength wording.

## No cross-category ordering

<!-- comparison-policy:forbidden-terms:start -->
Do not collapse performance, diagnostics, recovery, migration, ecosystem, and
verification into an aggregate score or tool ranking. The categories have
different semantics and trust boundaries. Publish each observation and its
limitations separately. Numeric totals never imply semantic equivalence.
<!-- comparison-policy:forbidden-terms:end -->

## Review and update workflow

1. Add evidence without deleting unfavorable or failed rows.
2. Add or update the claim in canonical claim-ID order. Keep corpus and evidence
   entries ordered by ID and path.
3. Mark unavailable tools or facts `not_compared` or `unknown`; do not estimate
   values.
4. Bind measured wording with claim markers or pending tables and conclusions
   with evidence markers. The body must retain the exact registered wording.
5. After reviewing an intentional marker-body diff, run the quality task. Its
   mismatch reports both the registered and actual SHA-256; copy the actual
   digest into `body_sha256` only in the same reviewed change. Never refresh a
   digest merely to make the task pass.
6. Run `bundle exec rake quality:comparative_claims`, the focused tests, and
   documentation coverage.
7. When a review condition fires, either remeasure under a new claim ID or
   narrow the old wording to its historical scope. Historical observations are
   retained rather than rewritten as current results.
