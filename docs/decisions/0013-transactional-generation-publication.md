# ADR 0013: Publish generated artifacts as a verified transaction

- Status: Accepted
- Date: 2026-07-28

## Context

One generation can produce Ruby, RBS, static action source, reports, and
metadata. Writing outputs as renderers finish can expose a mixed generation,
and filesystem aliases or a source change during generation can invalidate the
candidate being published.

## Decision

Generation renders every requested artifact in memory before changing output
paths. It records the exact input closure and revalidates it before
publication. Targets are resolved and checked for input aliases and
cross-output collisions.

Stages and recovery backups are created exclusively beside their targets.
Publication uses ordered locks, flushed and synchronized stages, atomic
renames, directory synchronization, and reverse-order restoration on failure.
Because a portable filesystem cannot atomically replace several paths, an
optional final manifest is the coherence marker: readers that need one
generation verify artifact digests against a stable manifest read.

Watch mode runs this same transaction only after a stable source closure is
observed; it never publishes a candidate built from changing inputs.

## Consequences

- Rendering, source races, and recoverable write failures do not intentionally
  publish a partial candidate as complete.
- Multi-file coherence requires the manifest protocol rather than an
  unsupported cross-file atomicity claim.
- Transaction and watch code pay filesystem synchronization and hashing costs
  in exchange for a recoverable publication boundary.
- The publication contract currently requires a POSIX filesystem that supports
  advisory locks, hard links, ordered renames, and directory `fsync`. Unsupported
  platforms fail explicitly; they are not silently treated as weaker transactions.
