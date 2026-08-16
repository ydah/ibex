# Investigations

This directory indexes the dated investigations that support the current
implementation and release boundaries.

- [E001: Existing repair semantics](E001-existing-repair-semantics.md)
- [E002: Syntax-only repair result](E002-syntax-only-repair-result.md)
- [H004: Conflict-explanation study](H004-conflict-explanation-study.md)
- [V004: Table-artifact fault injection](V004-table-artifact-fault-injection.md)
- [W-A: Stage A safety net](W-A-stage-a-safety-net.md)
- [W-B: Fix baseline](W-B-fix-baseline.md)
- [W-B: Stage B analysis](W-B-stage-b-analysis.md)
- [W-C: Bison import](W-C-bison-import.md)
- [W00: Strongest-design assumptions](W00-assumptions.md)

The inclusion test is an explicit question, date, evidence boundary, and
conclusion. Investigations do not silently become architecture decisions.

## Baseline reconciliation

The work-order records are the baseline, not competing feature specifications.
The current investigations reconcile to them as follows:

| Current record | Baseline relationship |
| --- | --- |
| E001 and E002 | Apply W00's bounded-analysis assumptions to the Stage A safety net in W-A; E002 extends the characterized repair engine rather than introducing a second one. |
| H004 | Uses W00's independent-evidence boundary and W-B's analysis facilities; its conflict-explanation study remains a separate human-usefulness gate. |
| V004 | Extends W-B's table-analysis boundary with fault injection; it validates the data-only artifact contract without promoting benchmark or runtime claims. |
| W-C | Is the implementation record for the Bison import boundary identified by W00 and the Stage B/analysis work in W-B. |

W00 remains the assumptions audit, W-A the Stage A safety net, W-B the fix and
analysis baseline, and W-C the import boundary. This mapping is the inclusion
test for adding another investigation: its question must be new, or it must
explicitly supersede one of these records.
