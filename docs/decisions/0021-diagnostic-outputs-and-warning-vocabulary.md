# ADR 0021: Keep diagnostic outputs deterministic and additive

- Status: Accepted
- Date: 2026-07-23

## Context

Ibex already stores normalization warnings in Grammar IR, exposes nullable/FIRST/FOLLOW analysis, and can build the same grammar
as LALR(1) or canonical LR(1). The command line does not yet expose the set analysis, distinguish precedence declarations that
cannot affect a production, or point out terminals that occur only below an unreachable rule. LALR merge conflicts can also be
reported without mentioning that the existing LR(1) backend avoids them.

Warning records are serialized in Grammar IR v1. Adding a warning kind must not make an old v1 document invalid or require a
consumer to understand presentation policy. Algorithm suggestions must remain advisory: they cannot change conflict counts,
generated tables, output selection, or exit status.

## Decision

`--emit=sets` emits one deterministic JSON object with `nullable`, `first`, and `follow`. Only nonterminals are keys because
FIRST sets for terminals are tautological and FOLLOW is undefined for terminals. Nonterminal keys, nullable names, and terminal
names inside each set are sorted lexically. This document is an analysis view, not another versioned IR.

Grammar IR gains two additive warning type names:

- `unused_precedence` means a precedence symbol occurs in no production RHS and is not an explicit production precedence
  override. This deliberately conservative definition avoids claiming that a declaration is useless merely because the current
  automaton happens not to need it for conflict resolution.
- `unreachable_terminal` means an explicitly declared terminal occurs in at least one production but no occurrence is reachable
  from the start symbol. A terminal with no production occurrence remains `unused_terminal`, avoiding duplicate warnings.

Both records retain the declaration location and the existing `{type, symbol, loc}` shape. Readers of Grammar IR v1 must treat
warning type names as an extensible vocabulary. No field shape changes, so `schema_version` remains 1 and old v1 documents load
unchanged.

After building with the default or explicit LALR algorithm, the CLI may build canonical LR(1) only when the LALR result has an
unexpected unresolved shift/reduce count or any reduce/reduce conflict. If LR(1) lowers either unresolved count, stderr receives
one positioned note giving the avoided counts and suggesting `--algorithm=lr1`. Expected shift/reduce conflicts alone do not
trigger the extra build. The note never changes the command result.

Mermaid and HTML remain presentation views over Automaton IR. Mermaid state and edge order follows Automaton IR order. The
self-contained HTML report embeds no remote assets; its search, conflict-state highlighting, and conflict-state one-hop filter
operate only on deterministic DOM attributes.

## Consequences

- Set output can be diffed and used in CI without depending on symbol interning order.
- New warning producers remain independent of CLI display and strictness policy.
- A warning emitted by a newer Ibex can appear in schema-v1 JSON without invalidating older records or changing the IR envelope.
- Canonical LR(1) is not built for successful or intentionally expected LALR grammars.
- Visualization features add no runtime dependency and work for resumed Automaton IR.
