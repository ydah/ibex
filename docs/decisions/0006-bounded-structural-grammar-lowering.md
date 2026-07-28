# ADR 0006: Lower grammar extensions structurally and under explicit bounds

- Status: Accepted
- Date: 2026-07-28

## Context

EBNF, parameterized rules, and inline rules can be represented as textual
macros, frontend-only closures, or structural transformations. Textual
expansion loses locations and can capture names; unbounded recursive expansion
can exhaust the Ruby stack or memory.

## Decision

The frontend represents extensions as AST structure. Normalization lowers them
into ordinary symbols, productions, and serializable action-composition plans
before automaton construction. Synthetic names cannot collide with source
identifiers, and generated productions retain source and expansion provenance.

Parameterized specializations are memoized by structural arguments. Recursive
work uses explicit worklists, rejects structurally growing cycles, and has a
total specialization bound. Inline substitution rejects recursive dependency
cycles and has a separate materialization bound for alternative products.
Opaque action fragments remain ordered data in Grammar IR rather than
generator-only closures.

## Consequences

- Every parser-construction algorithm consumes the same lowered Grammar IR.
- Resumed IR preserves extension semantics and source mapping.
- Some theoretically finite expansions may be rejected by conservative cycle
  or resource bounds; callers can raise size bounds deliberately.
