# ADR 0062: Declarative error recovery

- Status: Accepted
- Date: 2026-07-26

## Context

The compatible yacc `error` token is precise and programmable, but every
recovery point requires an explicit production. Applications also need a
bounded panic-mode fallback for common statement and container boundaries.
Lrama-style error reductions are useful for completing a semantic phrase
before reporting the following unexpected token, but they must not replace an
action that the grammar already accepts.

The two mechanisms have different purposes. Their ordering must be stable
across pull and push parsing, and old grammars must keep byte-for-byte table
behavior when neither declaration is present.

## Decision

Extended roots may declare one synchronization set:

```text
%recover sync: ';' '}'
```

The names must be unique declared terminals other than the synthetic `error`
terminal. On a syntax error, the runtime reports once and first attempts normal
yacc recovery. If a stack state can shift `error`, that path has unconditional
priority. Otherwise the runtime enters panic mode, discards input through the
same observable discard path until it sees a synchronization token, and pops
states until that token has a non-error action. The synchronization token is
retained and processed normally. EOF before synchronization rejects the parse.
Pull and push drivers retain the same recovery context between tokens.

Extended roots may also declare prioritized error reductions:

```text
%on_error_reduce expression statement
%on_error_reduce declaration
```

Each line is one equal-priority group and a later line has higher priority. In a
state with completed productions for declared nonterminals, the uniquely
highest-priority production is installed only in ACTION cells that would
otherwise be errors. Existing shifts, reductions, accepts, and conflict
decisions are unchanged. A tie between completed productions at the highest
priority installs nothing. The semantic action and normal reduction observers
run before the eventual error report.

Both policies are optional Grammar IR v2 metadata. Code generation emits a
runtime synchronization table only when synchronization is configured; absent
policies add no generated table field. Recovery declarations are root-only and
are rejected in compatible mode and fragments.

## Consequences

- Explicit `error` productions remain the most precise and highest-priority
  recovery mechanism.
- Synchronization recovery has deterministic pull/push behavior and uses
  existing error, discard, recovery-hook, and event contracts.
- Error reductions can improve the semantic stack at the point of diagnosis
  without changing any previously valid input action.
- Panic mode may discard a large region when the selected synchronization set
  is too sparse; grammar authors must choose structural boundary tokens.
- Grammar IR v1 cannot represent these policies and loads with both lists empty.
