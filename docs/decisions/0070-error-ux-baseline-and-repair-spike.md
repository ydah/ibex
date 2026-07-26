# ADR 0070: Error UX baseline and repair-spike decision

- Status: Accepted
- Date: 2026-07-26

## Context

Phase 14 requires evidence rather than a feature checklist: ten malformed JSON
examples, a public comparison with racc, and a measured decision for the
minimum-repair research track. Hand-copied prose would drift when LR states,
expected-token computation, or repair tie-breaking changed.

The comparison must preserve the clean-room boundary. Repair usefulness also
contains a human judgment that cannot be inferred solely from successful parser
acceptance.

## Decision

`tool/error_ux_snapshot.rb` deterministically builds the gallery JSON parser,
compiles a self-authored compatible grammar through the public racc executable,
and runs ten fixed malformed inputs. It never reads racc implementation files or
generated source. The committed version-1 JSON records:

- Ibex's exact message, unexpected token, expected tokens, LR state, location,
  caret source, and suggestions;
- the public racc `on_error` token/value observation;
- the selected bounded repair plan, cost, explored configurations, and result;
- a fixed human useful/not-useful assessment with a short rationale.

The generator is a byte-for-byte test and CI gate. The artifact follows
`schema/error-ux-v1.schema.json`; environment-sensitive timing is excluded. The
comparison is explicitly tied to the recorded racc version. The public summary
lives in `docs/error-ux.md`.

Eight of ten repairs are assessed useful, exceeding SP-4's majority threshold.
SP-4 is therefore go for the opt-in bounded minimum-cost, deterministic
single-plan feature accepted by ADR 0053. Exhaustive equal-cost CPCT+ repair-set
enumeration is not implied by this decision and remains outside the stable
contract.

## Consequences

- Error UX regressions become reviewable data changes.
- The comparison states exactly which public racc boundary was measured and
  avoids claims about custom application layers.
- Repair quality has a reproducible baseline instead of anecdotal examples.
- Human assessments are intentionally versioned and require review when an edit
  plan changes.
- The two trailing-comma misses identify a concrete future tie-breaking target.
