# ADR 0090: Pass proven RHS reads as positional action arguments

- Status: Accepted
- Date: 2026-07-27

## Context

The format-v4 values-only ABI removed location and live-stack arguments, but
still allocated one reduction-values Array for every semantic action. Public
runtime profiles showed those short-lived Arrays in both reuse and
new-instance measurements. Most profiled actions read at most four fixed
`val[n]` elements and neither mutate nor retain the container.

Blind source substitution would be unsound around strings, comments, method
receivers, assignments, and dynamically indexed reads. Changing an existing
marker's call shape would also make old generated files ambiguous to a newer
runtime.

## Decision

Parser table format version 5 adds `positional_action: true`. A marked
generated `_ibex_action_N` receives zero to four individual RHS values. It
cannot carry values, borrowed-values, location, composition, or location
context markers.

The generator first applies the existing values-only and borrowed-container
proofs. A deliberately narrow lexical path handles actions without Ruby
literal, comment, regexp, escape, or heredoc boundaries and rewrites only
unqualified, statically in-range `val[integer]` reads. Other actions are
tokenized with Ripper while preserving the complete token stream. That path
also converts a proven read-only parallel assignment such as
`left, right = val` to positional values. Both paths reject receivers and
collisions with generated parameter names. Every unsupported or unparsable
shape retains the format-v4 Array ABI. Ruby source and generated RBS
signatures use the same per-generation cached analysis.

The direct compact driver reads up to four RHS values before popping the
stacks and invokes the positional method without materializing an Array. If
the action installs a reduction hook, the driver materializes the hook's
pre-action values at that boundary. The generic driver also understands the
marker.

## Consequences

- The BCDice and Nokogiri CSS public reuse workloads avoid roughly nine and
  eleven allocations per parse in five-worker diagnostics; Namae avoids about
  three.
- Existing generated tables remain accepted under their original v1-v4 call
  shapes.
- Format-v5 tables with inconsistent positional markers fail before the first
  token is read.
- Conservative fallback can miss an optimization but cannot expose a mutable
  values container through the positional ABI.
