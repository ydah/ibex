# Independent error UX review rubric v1

This rubric defines the independent human review required by release gate R001.
It applies only to the ten observations in
[`json-errors-v1.json`](../test/fixtures/error_ux/json-errors-v1.json). The
observations and the maintainer's repair assessment remain normative historical
evidence; an independent record is a separate artifact and never silently
rewrites them.

The machine-readable record contract is
[`error-ux-review-v1.schema.json`](../schema/error-ux-review-v1.schema.json).
The current gate state and immutable kit identity are published in
[`error-ux-review-status-v1.json`](error-ux-review-status-v1.json).

## Reviewer qualification

The reviewer must provide their canonical GitHub login, display name,
affiliation, and relevant conflicts of interest. They must compare that login,
case-insensitively, with the complete maintainer roster embedded in the kit;
the v1 roster includes `ydah`. A rostered maintainer cannot satisfy the gate.
An `@login`, profile URL, display-name alias, or maintainer-selected substitute
is not an identity. The review must be the reviewer's own assessment. A
maintainer may answer reproduction questions but must not choose labels or
rewrite rationales.

The reviewer evaluates only what the fixed evidence exposes. The Racc column is
the public `on_error` callback without an application-specific message layer.
The repair column is Ibex's selected opt-in bounded repair, not a claim about
Racc recovery. Ten cases cannot establish a general error-experience ordering.

## Fixed labels

Choose exactly one diagnostic label for every case:

- `useful`: the diagnostic identifies the relevant location and gives enough
  concrete information to guide the next correction.
- `not_useful`: the diagnostic is materially misleading, points at the wrong
  place, or does not provide actionable information for this input.
- `unclear`: the reviewer cannot decide from the fixed observation or the
  diagnostic has important helpful and unhelpful aspects.

Choose exactly one repair label for every case:

- `useful`: applying the displayed plan is a reasonable correction for this
  malformed input and does not introduce an unexpected semantic direction.
- `not_useful`: the plan completes parsing but is not a reasonable likely
  correction for this input.
- `unsafe`: applying the plan could conceal or introduce a materially different
  meaning, or the fixed evidence is insufficient to rule that out.
- `unclear`: the reviewer cannot choose another label from the fixed evidence.

`unsafe` is deliberately repair-only. Do not translate these labels to a
numeric score. Each diagnostic and repair label requires its own non-empty
rationale.

## Review procedure

1. Check out the exact repository revision to be reviewed with no local source
   changes. Run `bundle exec ruby tool/error_ux_snapshot.rb`; it must report a
   byte-for-byte match.
2. Run `bundle exec ruby tool/error_ux_review.rb template review.json`. The
   generated draft records the exact repository, snapshot, grammar, Ruby, Racc,
   command, and host identities observed by the tool.
3. Inspect cases `EUX-01` through `EUX-10` in that order. Assign both labels and
   replace every rationale placeholder. Do not add, remove, reorder, or omit a
   case or a failure row.
4. Compare the independent repair judgment with the maintainer's `useful` and
   `assessment` fields in the normative snapshot. Record every disagreement,
   including disagreement with a diagnostic observation. A disagreement is
   retained in the review record; it is not resolved by editing the snapshot.
5. Set a stable record ID, canonical reviewer GitHub login, display name,
   affiliation, ISO 8601 review date, and conflict disclosure. Confirm the
   exact reviewed maintainer roster. Set all four structured consent fields—
   storage of identity, labels, and rationales, plus republication of the
   review—to `true`. Set `record_state` to `published` only after the assessment
   is final.
6. Publish that final payload JSON unchanged in a reviewer-controlled GitHub
   repository. The payload deliberately contains no URL or publication
   metadata, so its bytes can be committed without a self-referential commit
   hash. Send the canonical
   `https://github.com/<owner>/<repo>/blob/<40-hex-sha>/<nonempty-path>` URL to
   the maintainers. Branches, tags, commit-only URLs, issue or pull-request
   comments, releases, query strings, fragments, encoded traversal, and
   abbreviated revisions are not accepted.
7. Maintainers fetch the immutable blob and copy its bytes without any
   normalization into `docs/error-ux-reviews/v1/records/`. The separate status
   entry records its local path and SHA-256, canonical blob URL, derived raw URL
   and source identity, publisher login, and an import-vetting attestation. The
   release gate fetches those bytes again without redirects and uses GitHub's
   primary commit API to require that the publication author and reviewer's
   canonical login match. Network, authentication, redirect, byte, digest, or
   identity uncertainty fails closed. Maintainers may reject a malformed record
   but must not rewrite labels, rationales, or disagreement statements.

The generated file is intentionally a `draft`. A draft, a self-review, an
unpublished or locally reconstructed payload, a mutable or noncanonical link,
missing structured consent, placeholder text, or an incomplete assessment
cannot satisfy R001.

The import-vetting attestation records who checked the source bytes and identity;
it is not cryptographic proof of human independence, coercion resistance, or
the truth of an affiliation/conflict disclosure. Public account identity,
immutable source bytes, maintainer-roster exclusion, and reviewer-authored
publication are machine checked; the remaining human claims stay explicit
limitations.

## Interpretation

R001 passes when at least one independently authored, published record validates
against the closed schema, reproduces the immutable ten-case evidence, and is
listed without alteration in the public status registry. Additional independent
records are retained even when they disagree with each other or with the
maintainer assessment. Passing R001 completes this narrow external review gate;
it does not prove general diagnostic or repair superiority.
