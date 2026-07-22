# Lexer coverage

| Construct | Status | Notes |
|---|---|---|
| Nested action braces | Supported | Balanced recursively |
| Single, double, and backtick strings | Supported | Escapes and `#{...}` interpolation are skipped |
| `%q`, `%Q`, `%w`, `%W`, `%i`, `%I`, `%x`, `%r`, `%s` | Supported | Paired and single-character delimiters |
| Regular expressions | Supported | Conservative expression-prefix heuristic; character classes and flags supported |
| `#` comments and `?x` characters | Supported | Ignored for brace balancing |
| `<<ID`, `<<-ID`, `<<~ID` heredocs | Supported | Unquoted identifiers only |
| Quoted or dynamically constructed heredocs | Rejected | Position-bearing error |
| Grammar `#` and `/* ... */` comments | Supported | Removed before tokenization |
| `---- header`, `inner`, `footer` | Supported | Must begin in column one; order and duplicates retained |
