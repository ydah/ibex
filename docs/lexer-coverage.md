# Lexer coverage

| Construct | Status | Notes |
|---|---|---|
| Nested action braces | Supported | Balanced recursively |
| Single, double, and backtick strings | Supported | Escapes and `#{...}` interpolation are skipped |
| `%q`, `%Q`, `%w`, `%W`, `%i`, `%I`, `%x`, `%r`, `%s` | Supported | Paired and single-character delimiters |
| Regular expressions | Supported | Conservative expression-prefix heuristic; character classes and flags supported |
| `#` comments and `?x` characters | Supported | Ignored for brace balancing |
| `<<ID`, `<<-ID`, `<<~ID` heredocs | Supported | Terminators obey indentation mode |
| Single/double/backtick quoted heredocs | Supported | Quoted identifiers may contain any non-quote, non-newline text |
| Interpolated and multiple heredocs | Supported | Bodies are opaque; multiple openers on one line are consumed in order |
| Grammar `#` and `/* ... */` comments | Supported | Removed before tokenization |
| `---- header`, `inner`, `footer` | Supported | Must begin in column one; order and duplicates retained |
