# 0003: Action lexing boundary

- Status: Accepted
- Date: 2026-07-22

## Context

Ruby actions contain braces that do not delimit grammar actions. Full Ruby parsing is inappropriate because actions can refer
to parser-local variables and should remain opaque until code generation.

## Decision

Use a source cursor shared by the grammar lexer and a dedicated balanced action scanner. The scanner recognizes nested braces,
quoted and percent literals, interpolation, regular expressions selected by a conservative preceding-character heuristic,
comments, character literals, and Ruby's unquoted, single-quoted, double-quoted, and backtick heredocs. Heredoc openers are queued
until the end of their shared source line, then their bodies are consumed in declaration order. User-code separators are
recognized only at column one.

## Consequences

Action code remains byte-for-byte text in tokens. The supported lexical boundary is explicit and can grow independently from
grammar parsing. Valid Ruby constructs outside the documented coverage fail early instead of producing corrupted parsers.
