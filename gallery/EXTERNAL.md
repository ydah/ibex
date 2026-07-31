# External grammar policy

The committed gallery contains only grammars written for this repository.
Third-party grammar files are not copied into releases, fixtures, or generated
artifacts.

An optional external compatibility job may download a grammar at a pinned
revision after recording its source URL and license. It may publish only Ibex
diagnostics and aggregate measurements, never the downloaded source. Such a
job is evidence, not a package input, and must run without inspecting the
other parser generator's implementation or generated source.

The scheduled `bison:external` gate uses these exact inputs:

| Input | Revision and source | License |
|---|---|---|
| GNU Bison `calc.y` | [`akimd/bison@25b3d0e`](https://github.com/akimd/bison/blob/25b3d0e1a3f97a33615099e4b211f3953990c203/examples/c/calc/calc.y) | [GPL-3.0-or-later](https://github.com/akimd/bison/blob/25b3d0e1a3f97a33615099e4b211f3953990c203/COPYING) |
| jq `parser.y` | [`jqlang/jq@603db3f`](https://github.com/jqlang/jq/blob/603db3f57741d217ba651e61086b550a72148b83/src/parser.y) | [MIT](https://github.com/jqlang/jq/blob/603db3f57741d217ba651e61086b550a72148b83/COPYING) |
| PHP `zend_language_parser.y` | [`php/php-src@7b78eb4`](https://github.com/php/php-src/blob/7b78eb4fcc29c5cafa083c667558d0fe79c0c499/Zend/zend_language_parser.y) | [BSD-3-Clause](https://github.com/php/php-src/blob/7b78eb4fcc29c5cafa083c667558d0fe79c0c499/LICENSE) |
| PostgreSQL `gram.y` | [`postgres/postgres@d6eac69`](https://github.com/postgres/postgres/blob/d6eac691747499645f21398c9e305d7a671e0229/src/backend/parser/gram.y) | [PostgreSQL License](https://github.com/postgres/postgres/blob/d6eac691747499645f21398c9e305d7a671e0229/COPYRIGHT) |
| CRuby Bison-era `parse.y` | [`ruby/ruby@e51014f`](https://github.com/ruby/ruby/blob/e51014f9c05aa65cbf203442d37fef7c12390015/parse.y) | [Ruby License / BSD-2-Clause](https://github.com/ruby/ruby/blob/e51014f9c05aa65cbf203442d37fef7c12390015/COPYING) |

The gate also downloads current CRuby
[`parse.y@825c457`](https://github.com/ruby/ruby/blob/825c457945cdb0d07c6075846dc778b147224cbf/parse.y)
as a separate flagship analysis input. It contains Lrama extensions and is not
counted among the five GNU Bison grammars. That distinction is part of the
evidence: Ibex reports the structurally unsupported extensions instead of
claiming that its approximate automaton is the GNU Bison/Lrama automaton.

Every byte stream is SHA-256 pinned in `tool/quality/bison_external.rb`.
Downloads, Bison reports, and generated C stay in temporary directories and
are deleted by the job. The repository and packaged gems contain none of
those third-party artifacts.
