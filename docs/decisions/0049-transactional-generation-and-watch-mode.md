# ADR 0049: Publish complete parser generations and watch stable source closures

- Status: Accepted
- Date: 2026-07-25

## Context

A parser generation can produce Ruby, RBS, an action shadow, reports, visualizations, and state-specific metadata. Writing those
files as each renderer completes exposes mixed generations when a later renderer or write fails. A timestamp-only watch loop can
also publish bytes from different source revisions, miss included fragments or failed include attempts, and spin after a
persistent error.

Multiple filesystem paths add further ambiguity. Inputs can be reached through symlinks, output names can collide only on a
case- or normalization-insensitive filesystem, and a process can replace a symlink or lock path between validation and use.
No portable filesystem primitive atomically replaces an arbitrary set of files, so readers need an explicit publication marker
rather than a claim of cross-file atomicity.

## Decision

Every CLI generation first renders immutable `Artifact` values into an `ArtifactSet`; no output is changed until all requested
renderers have succeeded. `GenerationInput` records the canonical identity, digest, size, and lexical access paths of the exact
bytes consumed by the root grammar, fragments, IR input, and error-message file. Publication revalidates those records before
staging and at each publication boundary.

`GenerationTransaction` resolves output targets, rejects input aliases, hard-linked targets, and names that would collide under
Unicode NFC normalization plus case folding in one canonical parent directory. A persistent hidden sidecar lock is derived from
each canonical target. Locks are acquired in sorted order with nonblocking `flock` retries, so watch cancellation remains
responsive. Symlink, hard-link, pathname-replacement, and protected-inode checks fail closed before or during publication.

Stages and backups live beside each resolved target. Stages are flushed, synchronized, and assigned either the existing target
mode, the requested executable mode, or an umask-derived new-file mode. Existing files are hard-linked to private recovery
backups so the old public path remains readable. After synchronizing the directories, the transaction publishes ordinary
artifacts in target order, then the parser, and finally the manifest. Every group is followed by directory synchronization.
A failure before the final boundary restores installed files in reverse order and preserves any backup that could not be
restored. Cleanup attempts every stage, backup, and directory independently; a cleanup problem after a committed generation is
a warning and cannot roll back the published result. A relative or absolute final symlink remains a symlink and publication
replaces its resolved target.

`--manifest[=FILE]` opts into a deterministic version-1 JSON generation manifest. With no explicit path it is placed beside the
actual parser artifact, including when the root grammar was opened through a lexical symlink. It records canonical input files,
their aggregate and individual SHA-256 digests, generation options, and every non-manifest artifact's absolute path, digest, and
size. The schema is shipped as `schema/generation-manifest-v1.schema.json`; `GenerationManifest.validate_file` verifies both the
shape and current artifact bytes. `--check --manifest` compares the would-be parser, companion outputs, and manifest without
rewriting them.

The manifest is a publication marker, not a cross-file atomic transaction. A concurrent reader that needs a coherent generation
must read the manifest, read and verify every listed artifact, and retry from a newly read manifest if a file is missing or its
size or digest differs. Reading generated files without this protocol may observe the short publication interval between groups.

`--watch` applies this transaction to Ruby file generation. It polls portable fingerprints every 250 milliseconds and debounces
changes for 50 milliseconds. Fingerprints include file kind, identity, size, nanosecond timestamps, symlink spelling and resolved
target, and regular-file SHA-256. The successful watch set is the fixed root/message paths plus the latest resolved source closure
and include attempts. On failure it retains the last successful closure and adds current attempted paths and output paths, so
creating a missing include or repairing an output retriggers generation. A source change during render, lock wait, staging, or
publication cancels that candidate and retries through the debounce path. Duplicate unchanged errors are printed once, the last
successful generation remains published, and `SIGINT`/`SIGTERM` exit with status 130/143. A rollback failure is fatal.

Watch mode accepts a grammar file and Ruby file outputs only. It cannot be combined with stdin, `--from`, `--check`,
`--check-only`, or information-only options. `Ibex::RakeTask` rejects `--watch`; long-running process ownership belongs to the
caller rather than a timestamp-based file task.

## Consequences

- A renderer, source race, target race, or recoverable filesystem failure cannot intentionally publish a partial candidate as
  the completed generation.
- Consumers that opt into the manifest have a deterministic integrity contract and a portable coherence protocol.
- Watch mode follows canonical fragment dependencies and failed paths without platform-specific watcher dependencies.
- Persistent zero-content lock sidecars can remain beside generated targets. They are coordination state and are not artifacts.
- Polling and content hashing trade some I/O for portability and race detection. Multi-file readers that ignore the manifest
  protocol can still observe publication in progress.
