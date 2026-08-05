# H004 independent review records

Review the fixed machine artifact at
`test/fixtures/conflict_explanations/study-v1.json` without executing grammar
actions. For every case, use its state items, competing actions, bounded
witness, and repair section to identify the cause and choose an edit. Do not
copy `maintainer_hypothesis` as an answer; it exists so disagreement can be
retained after the blind task.

A record must match `schema/conflict-explanation-review-v1.schema.json`'s
`review_record` definition and contain exactly one review for each of
`H004-EXPR`, `H004-ELSE`, `H004-RR`, and `H004-MERGE`. Record your own cause and
edit text, usefulness labels, rationale, and disagreement. If the machine
artifact offers no verified repair, `chosen_edit` may describe a manual edit
and `repair_usefulness` should remain `no_verified_repair` unless there is an
actual proposal to assess.

The registry remains `HOLD` until it has at least two records from distinct
reviewers. Do not collapse disagreements into a majority label; preserve them
in each record and in the registry summary.
