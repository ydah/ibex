# ADR 0039: Attach rule documentation from lossless comments

- Status: Accepted
- Date: 2026-07-25

## Context

Grammar IR version 2 reserves documentation on symbols and productions, but semantic parsing deliberately discards comments.
Rule documentation must therefore correlate the generated semantic AST with ADR 0036's lossless segments without parsing source
text a second time. A raw source regular expression would incorrectly observe `##` inside opaque Ruby actions, heredocs, or
user-code bodies. Includes add a second requirement: documentation attached in a fragment must retain that fragment's location
and survive canonical resolution.

Repeated definitions of one rule need a deterministic symbol-level summary while preserving the documentation of each
production. Human-readable output must also escape untrusted grammar text, remain reproducible from serialized Grammar IR, and
avoid making parser generation execute application code.

## Decision

A documentation line is a lossless `line_comment` segment whose text begins with `##`. Optional indentation may precede the
segment. Attachment starts on the line immediately before a rule's LHS and walks backward across consecutive documentation
lines. Each line may contain only indentation, that one comment, and its newline. A blank line, ordinary `#` comment, block
comment, token, or opaque segment stops the walk. The frontend removes `##` and at most one following space from each line, joins
the retained lines with `\n`, and preserves empty and additionally indented content. CRLF uses the segment positions and follows
the same rule.

`Frontend::RuleDocumentation` indexes lossless segments by occupied source line. Multi-line opaque segments occupy every line in
their span and can never become documentation. After the generated parser returns, `Frontend::Parser` builds a new
`AST::Root` or `AST::Fragment` and new `AST::Rule` records with nullable `documentation`; it does not mutate the generated
parser's result. Token-array parsers have no source document and leave the field nil. Canonical Resolver merging and deep
freezing preserve fragment documentation and rule identity.

Every user production created from a documented rule receives that rule's documentation. The nonterminal `GrammarSymbol`
receives the first nonnil documentation among repeated definitions. A later nonnil value is accepted when identical and is a
positioned normalization error when different. Synthetic EBNF helper productions remain undocumented. Grammar IR version 2
serializes symbol and production `doc`; version 1 omits both keys exactly as before.

`Codegen::Documentation` deterministically renders user rules, descriptions, and alternatives as:

- escaped Markdown;
- self-contained, accessible, escaped HTML; or
- the existing self-contained railroad SVG.

Railroad sections expose the complete escaped description through `<desc>`, render documentation visibly, wrap it at a bounded
column count, and include the resulting line count in section and document height. Existing `--railroad` output therefore
reflects rule documentation without overlapping productions.

`ibex doc [--format=markdown|html|railroad] [-o FILE] [--mode=racc|extended] grammar.y` resolves the canonical include closure
and normalizes it without generating or running a parser. Without `-o` it writes to stdout. File output uses the established
same-directory atomic replacement behavior, preserves output symlinks and modes, refuses to alias the grammar input, and is not
replaced when parsing or normalization fails.

## Consequences

- Documentation attachment uses the exact comment/token stream that produced the AST and cannot see text inside opaque Ruby.
- Roots and included fragments share one deterministic documentation contract.
- Repeated rules retain production-level provenance without giving a symbol conflicting descriptions.
- Version-1 IR remains byte-shape compatible, while version 2 and resumed pipelines preserve documentation.
- Markdown, HTML, and SVG outputs escape source-controlled text and require no external assets or scripts.
- ADR 0040 propagates template documentation to parameterized specializations; inline user rules remain separate extension work.
