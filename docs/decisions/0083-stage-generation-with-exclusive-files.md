# ADR 0083: Stage generation with exclusive same-directory files

- Status: Accepted
- Date: 2026-07-27

## Context

Cold public-generator profiles showed that loading `tempfile` and `tmpdir`
formed a measurable part of short grammar generation. The generation
transaction used `Tempfile` both for a staged output and to reserve a name that
was immediately unlinked before creating a hard-link backup.

The transaction still requires same-directory staging, exclusive names,
durable flushes, atomic rename, hard-link backup, bounded collision handling,
rollback, and cleanup. A predictable unchecked filename or a temporary file in
another filesystem would weaken those guarantees.

## Decision

`GenerationTransaction` now creates staged files directly in the target
directory with `File::CREAT | File::EXCL`, plus `NOFOLLOW` where available.
Names contain the process, transaction object, and a monotonically increasing
transaction-local sequence. Name collisions retry up to 100 candidates.

Backups use the same candidate generator and call `File.link` directly. They
no longer create and unlink a placeholder before linking the target. Staged
files retain the existing binary write, flush, mode, `fsync`, atomic rename,
directory synchronization, rollback, and best-effort cleanup sequence.

## Consequences

- The ordinary generator no longer loads `tempfile` or `tmpdir` for
  transactional publication.
- File creation and backup reservation remain race-safe through exclusive
  create and hard-link semantics.
- Recovery tests fail the first real backup cleanup attempt instead of a
  discarded placeholder unlink.
- Exhausting the bounded candidate space produces a positioned generation
  error rather than retrying indefinitely.
