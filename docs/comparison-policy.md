# Comparative claim policy

This policy defines when Ibex documentation may compare Ibex with another
parser tool. The machine-readable registry is [`claims.yml`](claims.yml), and
`bundle exec rake quality:comparative_claims` validates the registry and its
public claim markers.

The initial comparison set is Racc, Lrama, GNU Bison, Menhir, Tree-sitter, and
ANTLR. A tool being in the set does not imply that a comparison has been made.
An unmeasured tool remains `not_compared`; unknown facts remain `unknown`.

## Required record

Every measured or review-pending claim records:

- an immutable claim ID and narrowly scoped wording;
- each subject's exact released version and, when applicable, repository
  revision;
- a public command with every material option;
- fixed corpus paths and external revisions;
- known environment values and an explicit list of unrecorded values;
- excluded or unsupported semantics;
- the subjective review method and its completion state;
- repository-relative evidence paths and explicit limitations; and
- an exact-revision validity scope, expiry statement, and conditions that
  require review.

`not_applicable` is valid only when an identity dimension does not exist, such
as a repository revision for a released gem identified by its exact version.
It must not conceal missing information. A measured environment may retain
`unknown` fields only when the limitation is published and the wording does not
generalize beyond the known conditions.

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
required independent review is missing stays `review_pending`; it cannot be
worded as a completed comparative conclusion.

Performance statistics and deterministic behavior digests do not require a
subjective reviewer, but their scope and limitations still require ordinary
code review.

## Scoped wording

Comparative wording names the claim ID and states the relevant revision or
release, corpus, measurement category, and important limitation. For example:

> At revision X, on corpus Y and environment Z, metric M had the recorded
> relationship to tool version V. This does not describe other revisions,
> workloads, backends, or semantic capabilities.

Do not publish wording such as “faster than Racc” or “better diagnostics”
without those boundaries. README comparative strength wording is enclosed by
`comparative-claim` markers. The validator requires a matching claim record,
existing evidence paths, and nonempty limitations; it also rejects unmarked
README paragraphs that combine a comparison tool name with strength wording.

## No combined ranking

Do not collapse performance, diagnostics, recovery, migration, ecosystem, and
verification into an aggregate score or tool ranking. The categories have
different semantics and trust boundaries. Publish each observation and its
limitations separately. Numeric totals never imply semantic equivalence.

## Review and update workflow

1. Add evidence without deleting unfavorable or failed rows.
2. Add or update the claim in canonical claim-ID order. Keep corpus and evidence
   entries ordered by ID and path.
3. Mark unavailable tools or facts `not_compared` or `unknown`; do not estimate
   values.
4. Bind public wording to the claim ID with matching start and end markers.
5. Run `bundle exec rake quality:comparative_claims`, the focused tests, and
   documentation coverage.
6. When a review condition fires, either remeasure under a new claim ID or
   narrow the old wording to its historical scope. Historical observations are
   retained rather than rewritten as current results.
