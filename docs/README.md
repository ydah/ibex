# Documentation hub

Ibex documentation is organized by layer. The [publication manifest](index.yml)
controls the site; directory placement alone never publishes a document.

## Entry points

- [Getting started](getting-started.md)
- [Grammar reference](grammar-reference.md)
- [Development and quality checks](development.md)

## Layers

- [`guides/`](guides/README.md) — task-oriented migration and setup guides.
- [`concepts/`](concepts/README.md) — subsystem behavior and boundaries.
- [`policy/`](policy/README.md) — compatibility, maturity, release, and trust rules.
- [`decisions/`](decisions/README.md) — durable architecture decisions.
- [`evidence/`](evidence/) — published evidence and review methods.
- [`records/`](records/README.md) — dated investigations, dossiers, and profiles.
- [`registry/`](registry/) — machine-readable sources of truth.
- [`generated/`](generated/README.md) — generated documentation output.

## Inclusion test

An entry-point, guide, concept, policy, or published evidence document must be
listed in [`index.yml`](index.yml). Internal Markdown records must be indexed by
the README in their containing directory. A document belongs to one layer only;
if its content spans layers, split the reader-facing explanation from the
decision or evidence record.

## Verification gates

`bundle exec rake quality:docs_coverage` verifies the Stable markers, publication
manifest paths and front matter, Markdown inventory, relative links, and the
exact ADR index. `tool/build_site.rb` consumes only `index.yml` and copies only
the manifest's assets.
