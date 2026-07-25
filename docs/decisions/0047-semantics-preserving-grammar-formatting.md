# ADR 0047: Format grammar trivia behind a semantic equivalence guard

- Status: Accepted
- Date: 2026-07-25
- Supersedes: the formatter boundary in ADR 0035

## Context

Ibex grammar files combine a line-oriented declaration language, nested extended EBNF, opaque Ruby actions, comments that can
carry documentation, and unconstrained user-code sections. A source formatter must understand root and fragment syntax without
mistaking braces or heredoc terminators inside Ruby for grammar structure. Reprinting the semantic AST would discard comments,
spelling, user-code block order, and exact action source. A purely lexical formatter could instead separate parameterized calls
from their opening parenthesis or move a documentation comment far enough to change its attachment.

In-place formatting also needs a stronger filesystem contract than an ordinary write. A truncated grammar is not an acceptable
failure mode, and updating a path through a symlink must update its target without replacing the link itself. Batch checking must
visit every requested source so CI reports all stale and invalid files in one invocation.

## Decision

`Frontend::Formatter` accepts only a source that the self-hosted frontend parses successfully into a `SourceDocument`.
`Parser#parse_source_document` is the root-or-fragment counterpart to the root-only `parse_document`; it attaches the generated
`AST::Root` or `AST::Fragment` to the same lossless document. The formatter uses semantic classifications from that document's
existing token array and never parses action or user-code text.

Formatting replaces only `whitespace` and `newline` trivia between protected CST segments. Ordinary token spelling, comments,
actions, user-code markers, user-code bodies, and their order remain byte-for-byte unchanged. Declarations, precedence levels,
conversion entries, rules, and outer alternatives receive deterministic line boundaries and indentation. Constant scopes,
formal and actual parameter lists, named references, suffixes, commas, and nested EBNF punctuation receive deterministic
adjacency. In particular, parameterized calls keep the callee adjacent to `(` and `%inline` stays on the same line as its LHS.
Heredocs remain part of their single opaque action segment.

Existing blank-line count and each existing `\n` or `\r\n` segment are retained when a line boundary is required; indentation
and trailing horizontal trivia are canonicalized. A newly required line boundary uses the source's first newline spelling,
including a newline inside an opaque action or user-code body, or `\n` when the source had none. Consecutive `##` comments stay
consecutive and immediately above their rule, preserving documentation attachment.

The formatted text is reparsed in the same `racc` or `extended` mode. An explicit work stack compares the two AST projections
without calling recursive `AST#to_h`; Struct members and Hash keys named `loc` or `span` are excluded. This keeps deeply nested,
otherwise valid EBNF within the parser's existing depth contract. Any parse failure or projection difference rejects the result.
Formatting is idempotent.

The CLI exposes:

- `ibex fmt grammar.y`, which writes the formatted source to stdout;
- `ibex fmt -` with optional `--stdin-filename=FILE`, which reads stdin and writes stdout;
- `ibex fmt --check a.y b.y`, which reports every invalid or noncanonical input and exits 1 when any is found; and
- `ibex fmt --write a.y b.y`, which validates and stages the whole batch before transactionally replacing changed files.

`--mode=racc|extended` selects the frontend mode. The subcommand owns a separate option parser, so parser-generation options are
rejected. Check and write modes accept filesystem inputs only. A stdin diagnostic name containing a control byte is rejected;
control bytes in filesystem paths are escaped in one-line diagnostics.

Before staging, write mode resolves every target and rejects duplicate paths, symlink aliases, and hard-link aliases. Each
changed file is staged in its target directory: binary content is written, flushed, and synchronized; the target's complete
permission mode, including special bits, is then applied and synchronized again. The transaction creates a same-directory
hard-link backup of every original and synchronizes every affected directory before installing any stage. It then renames every
stage into place and synchronizes every affected directory again. A rename or directory synchronization failure restores every
installed target from its backup in reverse order, attempts every affected directory synchronization, and reports the original
failure before rollback or cleanup failures. If a target cannot be restored, its exact hard-link backup is deliberately retained
and its path is reported.

Artifact cleanup is best effort: every remaining stage and removable backup is attempted, with one retry, without masking the
transaction's original failure. Cleanup failure after a committed batch cannot turn the committed update into an apparent
transaction failure; `fmt --write` reports a cleanup warning naming any remaining artifacts and exits successfully. A symlink
path resolves only for replacement, including a relative symlink, so the link itself remains unchanged. Invalid grammars are
never staged.

## Consequences

- Formatting shares the exact lexer/parser authority used by generation and cannot observe fake grammar syntax inside Ruby.
- Comments and opaque application code remain reviewable as authored, while grammar trivia becomes deterministic.
- Root grammars, explicit fragments, racc syntax, and extended nested EBNF use one formatter and one equivalence check.
- `fmt --check` is suitable for CI and reports the complete requested batch instead of stopping at its first problem.
- In-place updates preserve the existing path contract, full permission mode, and symlink identity, while a batch failure
  restores every target instead of leaving a partial update.
- A failed restore leaves a byte-exact backup for manual recovery, and post-commit artifact cleanup problems are reported
  without misrepresenting already-installed output as uncommitted.
