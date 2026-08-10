# W00: strongest-design assumptions

Date: 2026-07-31

This audit compares the current repository with the strongest-design baseline before any implementation from that design.
The design documents describe a v0.1-era baseline; the repository is at
v0.2.0 and several proposed foundations already exist.

## 1. Architecture decisions

The highest current decision number is `0018`, not the design's provisional
`0081`. The decision index is intentionally current rather than append-only,
and its scope gate excludes commands, test plans, maturity decisions, and
release evidence. New work must not create an ADR unless it satisfies that
gate.

## 2. Existing LALR references and property tests

This work is an extension of existing verification, not a greenfield verifier:

- `Ibex::LALR::Builder` retains an explicit `canonical_merge` reference
  strategy and the direct LALR implementation is tested for byte equality
  against it.
- canonical item, key, suffix-lookahead, direct-lookahead, and IELR tests use
  independently shaped reference implementations and fixed seeds.
- `test/property/pipeline_invariants_test.rb` generates fixed-seed grammars
  across SLR, LALR, IELR, and LR(1), checks deterministic IR, validates
  structural table invariants, and compares plain and compact tables.
- `Ibex::Samples` and `ibex samples` already generate fixed-seed bounded
  terminal sentences with an explicit worklist, exact minimum-cost analysis,
  and expansion/depth/token limits. Stage A extends this implementation with
  coverage-oriented selection and differential execution; it does not add a
  second sentence generator.
- the current tests are implementation tests. They do not yet expose an
  independent, user-facing verifier for supplied Grammar and Automaton IR.

Consequently `ibex verify` must reuse the published IR contracts and the
existing table simulator, but must not call the builder to decide whether the
supplied automaton is valid.

## 3. Benchmark baseline and gates

The current deterministic baseline is
`benchmark/results/v2/2026-07-28-4a740768d06b-ruby-4.0.0-arm64-darwin24.json`.
`benchmark/verify.rb` validates its schema and reproduces structural counts and
digests. Wall-clock time, RSS, and allocation observations are explicitly
non-gating; deterministic structure and digests are gating. CST and
incremental CST have separate versioned observations.

This is stronger and more specific than the design's assumed benchmark
baseline. New quality tasks must not turn local timing or RSS observations
into CI thresholds.

## 4. Gallery-equivalent assets

There is no `gallery/` directory. The repository does contain self-authored
calculator, JSON, INI, CSV, and tiny-language examples, plus representative
benchmark grammars and test fixtures. `rake grammar:test` already runs
grammar-declared examples with complete production coverage.

Those assets are reusable inputs, but they do not satisfy the gallery
contract: they have no per-grammar provenance/license documents, valid and
invalid corpora, or committed conflict/state expectations. Stage A therefore
adds a focused gallery rather than duplicating every example.

## 5. Schema inventory

The repository contains closed, versioned schemas for the current Grammar and
Automaton IR plus the independently versioned Lexer IR and generation,
diagnostics, coverage, simulation, benchmark, CST, and error-UX reports. The
current Grammar and Automaton validators reject old documents and unknown
fields.

No schema exists yet for `verify`, `equiv`, `diff`, `metrics`, `fuzz`, or
`reduce`. The T0 tools must read existing IR and publish separate report
schemas; they must not add fields to the frozen core IR.

## 6. Lexer implementation

The grammar frontend lexer is a hand-written cursor scanner. Generated
application lexers are normalized to Lexer IR, emitted as anchored
`Regexp` objects by `Codegen::RubyLexer`, and matched by
`Runtime::GeneratedLexer`. A DFA backend does not exist and remains a
post-v1 inventory item; it is not required by Stages A--C.

## Differences that change the work

1. Work starts from v0.2.0, not v0.1.0.
2. The current ADR maximum is `0018`, and operational specifications must stay
   outside `docs/decisions/`.
3. Property and reference coverage already exists, so the matrix and verifier
   generalize it instead of replacing it.
4. Existing examples are gallery inputs, not a completed gallery contract.
5. The current core IR and table format v6 are already frozen; T0 remains read-only
   with respect to those schemas.
6. Red/Green CST batch parsing is already selected Stable; incremental CST
   remains Experimental.
7. The release report currently holds v1.0 for two measured product gates
   unrelated to the new T0 tooling. Completing this design does not permit
   falsifying that release decision.
## Implementation scope after audit

- Stage A: add the declared matrix, golden/reproducibility gates,
  coverage-oriented sentence selection plus fuzz/reduction, a licensed
  self-authored gallery, and adversarial CI without replacing existing
  property suites or `Ibex::Samples`.
- Stage B: add read-only analysis commands and report schemas around the
  existing IR, simulator, conflict, and source infrastructure. Verification
  remains independent of builder implementation.
- Stage C: finish catalog-based diagnostics and analysis-only Bison import,
  update the stability/public documentation inventory, and add reproducible
  release checks. Existing release KPI results remain evidence-based.
- Stage D/T1 remains an inventory and is not implemented as part of this
  work, as required by the design.
