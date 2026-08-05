# H004 independent review records

During blind collection, review only
`docs/conflict-explanation-reviews/v1/blind-study-v1.json`. Do not inspect the
source study, review registry, implementation, or repository history until the
submission has been sealed. The blind artifact uses neutral IDs and excludes
the source case ID, shape, grammar path, and maintainer hypothesis. For every
case, use its state items, competing actions, bounded witness, and repair
section to identify the cause and choose an edit without executing grammar
actions.

A record must match `schema/conflict-explanation-review-v1.schema.json`'s
`review_record` definition and contain exactly one review for each of
`H004-BLIND-01` through `H004-BLIND-04`. Copy the blind artifact SHA-256 into
the record, set `submitted_before_reveal` to true only when accurate, record
your own cause and edit text, and leave `reveal_comparison.status` as `pending`.
If the machine artifact offers no verified repair, `chosen_edit` may describe a
manual edit and `repair_usefulness` should remain `no_verified_repair` unless
there is an actual proposal to assess.

The registry remains in `blind_collection` and `HOLD` until it has at least two
records from distinct reviewers. Only then may the source study be revealed.
During `reveal_comparison`, map every neutral ID to its source case, bind the
source study digest, and record cause/edit alignment plus notes without
rewriting the original blind answers. The registry reaches `review_complete`
and `PASS` only when every record has a completed reveal comparison. Do not
collapse disagreements into a majority label; preserve them in each record and
in the registry summary.
