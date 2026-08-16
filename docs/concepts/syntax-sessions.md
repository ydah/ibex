---
title: Generated-language syntax sessions
description: Use bounded syntax-only editing sessions with immutable diagnostics and repair proposals.
---

# Generated-language syntax sessions

The Experimental syntax-session API is a generated-language service boundary,
not an LSP implementation. It reuses the existing incremental Red/Green CST
engine and returns syntax only: parser production actions never run and no
semantic value is available.

## Trust must be acknowledged

Current generated parser classes report exactly one execution profile:

```ruby
Calculator.syntax_execution_profile
# => :trusted_application_code
```

Opening a session requires the caller to acknowledge that profile:

```ruby
session = Calculator.syntax_session(
  "1 + 2",
  execution_profile: :trusted_application_code
)
```

Generated lexer actions execute while opening and editing a session because
they define token emission, conversion, and lexer-state changes. Loading the
generated Ruby class may already have executed `header`, `inner`, or `footer`
sections. The explicit keyword records caller intent; it is not a sandbox flag.
Omitting it raises `Ibex::Runtime::SyntaxSessionTrustError` before lexing.

There is no `:declarative` switch. That profile will require a separately
generated action-free parser artifact, a declarative built-in-only lexer, and
no user-code sections. The current generator does not produce such an artifact,
and overriding `syntax_execution_profile` cannot enable it.

Parser callbacks and generated lexer hooks are application code too. The
syntax-only guarantee is specifically that grammar production actions are
suppressed. Use this API only with generated artifacts already trusted by the
host process.

## Opening, editing, and results

Input is a `String` or `Ibex::Runtime::CST::SourceText`. Edits are
`Ibex::Runtime::CST::TextEdit` values expressed as zero-based, half-open byte
ranges against the current source:

```ruby
edit = Ibex::Runtime::CST::TextEdit.new(
  start: 4,
  delete_length: 1,
  insert_text: "3"
)
result = session.apply_edits([edit])

result.revision        # 1
result.syntax_root     # immutable Red root
result.diagnostics     # immutable diagnostics
result.expected_tokens # expected terminals observed at parser failures
result.status          # :ok or :syntax_error
result.metrics         # immutable reuse/fallback evidence
```

`expected_tokens` reuses the generated parser's current ordinary or exact
lookahead-correction policy. With several recoverable failures it is the
first-seen union for that operation; it is not a completion ranking.

The result and metrics snapshots are frozen. Metrics always describe the
installed result of the completed operation. `token_count` is the number of
entries in that result's final token memo, including parser-supporting tokens
represented there. `reused_tokens` is the number of those entries whose Green
token identity was reused from the preceding memo. It is zero for an initial
open and for a full fresh-parse fallback. `reused_ratio` is the parser's
completed structural-reuse ratio (or lexical ratio when the Blender is
disabled), so it is not generally `reused_tokens / token_count`.

`fallback?` and `fallback_reasons` distinguish a clean incremental operation
from a successful fallback. A full lexical-error fallback reports no reuse.
A decomposition or memo-budget fallback may still report independently
validated lexical token reuse even though subtree reuse or memo retention was
declined. Every fallback remains a valid syntax result.

Fresh syntax sessions are the reference semantics. Incremental results must
match fresh results in source bytes, Green structure and flags, and diagnostic
content.

## Syntax-only repair proposals

`SyntaxSession#repair` is an additive Experimental operation for editor-style
syntax proposals. It runs the bounded repair search on a fresh private parser,
captures token identity and byte ranges, applies the resulting
`CST::TextEdit` values to a new `CST::SourceText`, and validates the edited
source with another fresh syntax session. The originating session and source
are unchanged.

```ruby
proposal = session.repair(token_text: { "PLUS" => "+" })
proposal.status          # :accepted, :progress, :rejected, or a bounded failure
proposal.text_edits      # immutable byte edits
proposal.updated_source  # exact edited bytes, when validation ran
proposal.validation      # fresh syntax-only result, when validation ran
```

The result is deliberately syntax-only: it has no semantic `value`, never
replays production actions, and never invokes the application's `on_repair`
callback. `token_text` supplies source bytes only. Named inserted or replaced
tokens fail closed when no spelling is supplied; punctuation literals may be
derived conservatively. `:exhausted` and `:not_found` remain distinct bounded
outcomes, while overlapping edits and multiple selected repair segments are
reported as unavailable.

An accepted result requires zero diagnostics and complete source consumption.
For progress or rejection, `updated_source` retains the exact edited bytes and
the validation CST may expose only its consumed prefix, as permitted by the
existing error/early-accept CST contract. Cancellation and service limits raise
their existing exceptions and are never returned as successful proposals.

## Validation, cancellation, and limits

A source passed directly as a String must have an ASCII-compatible Ruby
encoding. `SourceText` and `TextEdit` are explicit byte containers and have
already normalized their text to binary, so binary strings and invalid UTF-8
bytes remain supported. A direct non-ASCII-compatible source such as UTF-16 is
rejected instead of being silently reinterpreted. Edit shape, nonnegative
offsets and lengths, overlap, and source bounds are validated by the existing
`TextEdit` and `SourceText` contracts.

`SyntaxSessionLimits` bounds source size, edit count, and inserted bytes. The
existing `ResourceLimits` independently bounds parser stack/recovery work,
incremental decomposition, and memo storage:

```ruby
limits = Ibex::Runtime::SyntaxSessionLimits.new(
  max_source_bytes: 2 * 1024 * 1024,
  max_edits_per_operation: 128,
  max_inserted_bytes: 256 * 1024
)
parser_limits = Ibex::Runtime::ResourceLimits.new(
  max_incremental_decomposed_nodes: 20_000,
  max_session_memo_bytes: 8 * 1024 * 1024
)
```

Exceeding a service or parser bound raises
`SyntaxSessionResourceLimitError`. It is never returned as an `:ok` result.
Incremental decomposition or memo exhaustion may instead use the existing
sound fresh-path fallback and records that decision in metrics.

Cancellation is cooperative:

```ruby
token = Ibex::Runtime::CancellationToken.new
session = Calculator.syntax_session(
  source,
  execution_profile: :trusted_application_code,
  cancellation: token
)

token.cancel!
session.apply_edits(edits) # raises SyntaxSessionCancelled
```

Checks run before an operation and at synchronous parser runtime events. A
cancellation requested after the final event belongs to the next operation;
this keeps completion and publication one atomic session transition. A Ruby
lexer action that does not return cannot be preempted; resource bounds and
cancellation do not isolate its side effects. An edit cancelled at a checkpoint
or stopped by a hard resource error leaves the last completed source and result
installed, and is never confused with a successful parse. Calls to
`apply_edits`, `source_text`, and `result` are serialized by the session.

## Scope and packaging

The prototype lives in `ibex-runtime`. A deployed generated parser needs only
the runtime's parser tables, lexer, CST engine, and session façade; requiring
the generator gem would unnecessarily add grammar construction concerns.
A separate `ibex-workbench` package is deferred until there is evidence for a
larger editor-service product boundary.

This API does not define LSP transport, workspace or file-system semantics,
cross-file indexing, query languages, formatting, or a declarative lexer. The
existing grammar-authoring LSP remains a separate static tool and does not load
generated application parsers.
