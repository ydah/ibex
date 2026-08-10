---
title: Project site strategy
description: Information architecture and implementation boundaries for the Ibex public site.
---

# Project site strategy

The public site is an adoption path rather than a catalogue of every internal
feature. The intended sequence is:

```text
understand → try → install → investigate → verify → contribute
```

## Information architecture

- The README answers the installation and first-parser decision in roughly 90
  seconds.
- Pages provides the task-oriented documentation hub, with Getting Started,
  Guides, Reference, Concepts, Examples, Playground, API, and Project areas.
- Compatibility, Extensions, Experimental, Gallery, Playground, and API keep
  their existing URLs. They are canonical landing pages or redirects, not
  discarded history.
- Stable, Preview, and Experimental are feature metadata. They do not become
  separate product versions or imply multiple persisted IR versions.

## Content rules

Public copy must distinguish racc migration compatibility from a claim of
byte-for-byte replacement, bounded evidence from proof, and trusted generated
Ruby from sandboxed execution. Comparative claims link to their complete
evidence record. Maturity is read from `docs/maturity.yml`; prose does not
duplicate a second feature registry.

## Build and safety rules

`tool/build_site.rb` is the canonical static builder. It reads docs source,
renders the selected documentation pages, copies the canonical landing pages,
and emits the Playground bundle into `tmp/site`. The builder must remain
reproducible, self-hosted, and free of runtime gem dependencies. Every page
uses a strict same-origin CSP, has a skip link and canonical metadata, and
does not send grammar source to a third party. Playground actions remain
non-executing, bounded, and worker-isolated.

The implementation is intentionally framework-free. A framework migration is
only worth revisiting if versioned documentation, multilingual content, large
faceted search, or builder maintenance becomes a demonstrated cost.

## Operational review

Review the site with keyboard navigation, narrow viewports, zoom, reduced
motion, link/anchor checks, and a clean rebuild. New feature claims must point
to the maturity registry and evidence rather than being inferred from a
landing-page badge.
