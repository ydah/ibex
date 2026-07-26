# 0051: Deterministic runtime coverage

- Status: Accepted
- Date: 2026-07-25

## Context

Grammar tests need to answer which parser states and productions they exercised without depending on private runtime stacks.
Coverage must be safe to aggregate across test processes, must reject traces from different generated parsers, and must not
silently treat a truncated trace as complete. Running generated parsers or application semantic actions inside the coverage
command would also give a report-reading tool an inappropriate code-execution boundary.

## Decision

Coverage consumes only complete schema-v1 runtime-event JSON Lines sessions. Each session begins with sequence 1 `start`, has
contiguous sequence numbers, and ends with `accept` or `reject` before another session may begin. Collection requires the full
generated-parser grammar digest, table format version, state count, and production count from `start`; handwritten tables whose
metadata is unavailable are rejected.

A state hit means entry through the initial `start` state, an ordinary `shift` destination, a `reduce` goto destination, or a
successful `recover` destination. A production hit means a committed `reduce`. Counts record visits, while threshold percentages
use the number of distinct ids. IDs must be inside the declared totals.

`runtime-coverage` schema version 1 contains the full grammar digest, table format, totals, session and event counts, and ascending
`{id,count}` state and production arrays. It contains no clock, host, input path, semantic value, or parser object. The JSON is
therefore deterministic for the same event multiset. Readers limit an event line to 1 MiB, JSON nesting to 32, a report to 16
MiB, declared totals to one million, and counters to signed 64-bit maximum values. Invalid UTF-8, sequence gaps, incomplete
sessions, duplicate or unsorted IDs, unknown fields, and arithmetic overflow fail closed.

`ibex coverage collect EVENTS.jsonl [-o REPORT]` creates a report without executing the parser. `coverage merge` adds reports only
when digest, table format, and totals are identical. `coverage check` compares distinct state and production percentages with
independent `--min-states` and `--min-productions` thresholds and exits nonzero when either fails. File output is an atomic,
mode-preserving replacement, including through an existing symlink; input/output aliases are rejected.

The contract is published as `schema/runtime-coverage-v1.schema.json`.

## Consequences

- Parallel test shards can produce deterministic reports and merge them without loading generated or application Ruby.
- A completed report cannot accidentally combine different generated parser revisions or an interrupted session.
- Coverage counts committed runtime behavior, including recovery, rather than static reachability.
- Mid-session observer attachment and handwritten tables without coverage metadata cannot be collected; attach the event tracer
  before parsing and regenerate parsers with current metadata.
