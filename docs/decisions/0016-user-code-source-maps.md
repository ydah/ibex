# ADR 0016: Preserve user-code chunks for source mapping

## Context

The compatible CLI has three source-line modes. Black-box observation of racc 1.8.1 shows that the default maps semantic
actions and `inner` user code to the grammar file, `--line-convert-all` additionally maps `header` and `footer`, and `-l`
disables all mappings. Ibex previously mapped semantic actions only because Grammar IR retained concatenated user-code strings
but discarded the location of each original block.

Repeated `header`, `inner`, and `footer` blocks may be separated by arbitrary grammar text, so one location per section is not
enough. Generation resumed from Grammar IR or Automaton IR must also behave identically to direct `.y` generation.

## Decision

Grammar IR v1 keeps the existing concatenated `user_code` field and adds optional `user_code_chunks` metadata. Each chunk stores
its code and the location of its first code line. The addition is backward compatible: old v1 JSON without the field still
loads, and dumping such an object does not synthesize the field.

The Ruby generator evaluates mapped chunks with the current lexical binding and supplies the grammar filename and line to
`eval`. Unmapped chunks remain literal generated source. The default maps actions and `inner`; `--line-convert-all` maps every
section; `-l` maps none. Explicit all-code conversion fails with a positioned error when non-empty user code lacks chunk
metadata instead of silently claiming a mapping it cannot provide.

## Consequences

- Direct and resumed pipelines preserve identical line mappings.
- Existing consumers of `user_code` and old schema-v1 JSON remain valid.
- Grammar IR JSON grows only when source chunk metadata exists.
- User code remains opaque Ruby; this metadata does not parse or transform it.
