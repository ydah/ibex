# H003 independent review records

Review the byte-bound machine evidence in
[`error-ux-round2-v1.json`](../../../round2-v1.json). The repository
capture is complete, but it is not an external judgment. Do not copy a
repository-authored risk statement into a review without independently
assessing the diagnostic, caret, proposed edit, fresh-reparse result, and
semantic-value risk.

An accepted record must match the `review_record` definition in
[`error-ux-round2-review-v1.schema.json`](../../../../../../schema/error-ux-round2-review-v1.schema.json)
and is published in the `records` array of the
[`H003 status registry`](../../../round2-review-status-v1.json).
It must identify an external reviewer, attest independence and publication
consent, bind the exact evidence SHA-256, and include exactly one assessment
for each of the seven required case IDs. Each assessment needs one of
`useful`, `misleading`, `unsafe`, or `unclear`, a rationale, and a separate
semantic-value risk assessment.

The registry stays `HOLD` until at least two normalized-distinct external
reviewers have complete records. Reviewer names are compared after Unicode
NFKC normalization, full case folding, trimming, and whitespace collapse. If
their labels differ for any case, retain
every reviewer pair and its two labels in `disagreements`; do not collapse
them into a majority label. The quality gate verifies that disagreement
inventory against the records.

This directory intentionally contains no example or placeholder record.
Adding reviewer-looking data without a real external review would fabricate
evidence.
