---
title: Project status
description: Human-readable release status, maturity boundaries, and evidence links for Ibex.
---

# Project status

Ibex is pre-1.0. The default compatible mode is the conservative adoption
baseline, while Preview and Experimental features require explicit activation
and have feature-specific boundaries.

## Release decision

The v1.0 publication decision is currently on hold because the published error
experience evidence still needs an independent review. This blocks publication
of that release candidate; it does not freeze feature development. The current
Grammar IR, Automaton IR, table, report, and runtime contracts remain closed
and validated while Preview work continues under the stability policy.

The complete rationale and evidence limitations are in the [release readiness
report](release-readiness.md). The [error UX review status](../evidence/error-ux-review-status-v1.json)
is the machine-readable record; this page is the human entry point.

## Maturity at a glance

- **Stable baseline:** racc-compatible grammar input, default LALR construction,
  current parser/runtime contracts, and format-v6 batch CST.
- **Preview:** extended grammar syntax, generated lexers, IELR, LSP, watch,
  diagnostics, and the browser playground. These require explicit activation
  or are bounded tools.
- **Experimental:** syntax-only incremental CST sessions and selected research
  surfaces. They may change without the Stable compatibility promise.

Consult [maturity.md](maturity.md) and [stability.md](stability.md) for the
canonical feature registry, activation mechanism, and promotion requirements.

## Evidence boundaries

Repository tests and bounded benchmarks are evidence for the recorded revision,
not universal performance claims. Comparative statements link to the relevant
[comparison policy](comparison-policy.md), [workload registry](workloads.md),
and release artifact. Ibex does not claim to be a sandbox: generated semantic
parsers execute application Ruby.
