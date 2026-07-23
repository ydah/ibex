# 0028: Render railroad diagrams from normalized Grammar IR

- Status: Accepted
- Date: 2026-07-23

## Context

Railroad diagrams are useful before parser-table construction because they explain the grammar rather than the generated
automaton. Ibex's extended grammar syntax is lowered to ordinary productions during normalization, and resumed Grammar IR must
produce the same diagram as source input. A visualization file may also contain user-controlled class, symbol, literal, and
display names.

## Decision

`Ibex::Codegen::Railroad.render` accepts only normalized `IR::Grammar` and returns one self-contained SVG document. It embeds its
styles and has no scripts, remote assets, or font dependency. Nonterminals follow Grammar IR symbol order, and each
nonterminal's alternatives follow production order. Every production receives its IR production id in a deterministic data
attribute.

The diagram shows the normalized production graph. Consequently, EBNF lowering helpers are separate nonterminal sections, while
their recorded `origin[:expression]` labels keep the original EBNF notation recognizable. Empty productions use an explicit
epsilon path. Symbol display names remain presentation-only and are resolved with the same label projection as other diagnostic
outputs.

Geometry uses fixed constants and label character counts rather than platform font measurement. Every grammar-derived string is
XML-escaped before insertion; grammar data is never interpreted as markup, style, or script.

The CLI option `--railroad=FILE` writes this SVG as a side output as soon as normalized Grammar IR is available. It therefore
works for source grammars, resumed Grammar IR, and resumed Automaton IR, independently of the selected post-normalization emit
format. Check-only mode does not write side outputs. `--emit=ast` does not normalize and therefore cannot produce a railroad
diagram.

## Consequences

- Source and resumed IR generate byte-identical diagrams.
- Lowered helpers and empty alternatives are inspectable without constructing parser states.
- Diagram generation adds no runtime or browser dependency.
- Very long labels enlarge the deterministic canvas instead of depending on renderer-specific text measurement.
