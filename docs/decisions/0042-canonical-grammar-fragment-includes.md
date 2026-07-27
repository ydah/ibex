# ADR 0042: Resolve canonical grammar fragments inside one source root

- Status: Accepted
- Date: 2026-07-25

## Context

Large grammars need reusable declarations and rules, but an include mechanism crosses parsing, filesystem security, source
locations, normalization order, IR provenance, command-line consistency, and incremental build dependencies. Treating an
included file as another root grammar would create ambiguous class, superclass, start, option, and user-code ownership. Textual
concatenation would also obscure locations, duplicate diamonds, and make symlink aliases evade cycle checks.

Grammar IR version 2 already reserves a source root and production include chain. The lossless frontend already retains source
locations. The remaining contract must distinguish roots from fragments, keep the normal source-only parser free of I/O, and
define one deterministic and contained filesystem traversal.

## Decision

Includes are an extended-mode feature. A root uses its existing form and may place `include "relative/path.y"` among ordinary
declarations. `--mode=extended` or the root's preceding `pragma extended` enables the syntax. An included file has the explicit
form:

```text
fragment
  declarations
  include "nested.y"
rule
  zero_or_more_rules
end
```

A fragment has no class or superclass and cannot contain `pragma`, `options`, `expect`, `start`, or `----` user-code blocks.
Token, precedence, conversion, display, and type declarations are composable. Nested fragments may include other fragments.
Paths must use double-quoted literals.

`Frontend::Parser#parse` keeps its `AST::Root` contract and rejects fragment input.
`Frontend::Parser#parse_fragment` returns an `AST::Fragment` without performing filesystem access. Parsing a root with include
nodes also performs no I/O. `AST::Include` retains the decoded path and include-site location.

`Frontend::Resolver.new(root_path, mode:).resolve` is the filesystem boundary. It returns an immutable `Resolution` containing
the merged root AST, canonical root path and directory, deterministic dependency list, and each rule's include chain. Resolution
uses depth-first traversal at each include declaration. Included declarations and rules are inserted in that order; a canonical
file already completed through another branch is not inserted again, so a diamond uses its first DFS occurrence. Before
exposure, `Resolution` recursively freezes every owned AST struct, array, hash, string, and location. It preserves resolved
`AST::Rule` identity for include-chain lookup, but defensively copies and recursively freezes provenance strings and byte spans.

`File.realpath` is the identity for visiting, completed, cycle, and dependency records. A cycle reports the exact canonical loop
from its first repeated member back to itself. Include paths are relative to the including file. Absolute and Windows-absolute
paths, parent traversal components, glob metacharacters, NUL, missing paths, and non-files are rejected. After symlink
resolution, every target must have the canonical root grammar directory in its `File.dirname` ancestry. Walking parents to
their fixed point avoids string-prefix ambiguity and works when the allowed directory is a filesystem or drive root. This also
makes symlink aliases participate in cycle detection and prevents symlink escape.

The Normalizer rejects an unresolved `AST::Include` or `AST::Fragment`. Passing a `Resolution` supplies Grammar IR version 2
with the canonical root directory in `source_provenance.root`, the original rule file in `origin.loc`, and a complete
`expansion.include_chain`. ADR 0043 later attaches lossless rule documentation before resolution; fragment documentation follows
the same merge, location, identity, and deep-freeze rules and populates version-2 symbol and production fields. Version-1
production serialization still omits all version-2 documentation and expansion fields. ADR 0044 later treats parameterized
definitions in fragments as templates and retains each definition's include chain on every specialized production.

Every CLI command that consumes a grammar path uses the same Resolver, including generation, checks, AST/IR output, diagnostics,
`explain`, `samples`, and `errors`. `ibex diagnose` turns the first resolver grammar failure into an immutable syntax-phase
`frontend.resolution_error` and emits its normal text or schema-valid JSON result with no AST. This bounded cross-file behavior
does not attempt recovery in multiple fragments. `Frontend::ResolutionIOError` distinguishes actual permission/read failures,
which continue through the CLI invocation-error path on stderr without JSON. Programmatic callers with source strings must opt
into Resolver to authorize I/O.

`Ibex::RakeTask` resolves and validates the same canonical DFS closure while defining the file task. Invalid grammar or include
graphs therefore fail task definition before Rake can treat an existing target as current. A valid closure records every
included fragment as a prerequisite, so changing any one invalidates the output.

## Consequences

- Root ownership and fragment composition are explicit rather than inferred from filenames or missing declarations.
- Locations and duplicate-declaration diagnostics identify the original canonical source file.
- Diamond graphs are deterministic and cycles cannot be hidden by symlink aliases.
- Includes cannot escape the root grammar directory, even when a textual path appears local.
- Resolution objects cannot be mutated through AST, location, or provenance aliases.
- Diagnostics distinguish grammar-graph failures from actual filesystem I/O failures.
- Invalid Rake graphs cannot silently reuse a stale generated target.
- CLI, Rake, and normalized IR observe one include order and one dependency closure.
- Parameterized and inline rules remain separate extension work.
