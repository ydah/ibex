# ADR 0084: Load CLI features at their invocation boundary

- Status: Accepted
- Date: 2026-07-27

## Context

The executable requires `ibex/cli`, but that file previously required the
umbrella `ibex` library and every subcommand mixin before parsing its
arguments. A normal parser generation consequently loaded coverage,
table-simulation, migration, grammar-test, sample, documentation, and language
server implementations that could not affect its output. This work inflated
the cold-generator measurements defined by ADR 0082 and made CLI source files
depend on the incidental ordering of the umbrella require list.

The public `require "ibex"` entry point remains the complete library surface.
CLI mixin constants exposed after `require "ibex/cli"` also need to remain
resolvable. Help, version, errors, all generation options, and every
subcommand must retain their existing behavior.

## Decision

`ibex/cli` declares the dependencies of the ordinary grammar-to-Ruby
generation pipeline directly. It does not require the umbrella entry point.
The common CLI class includes only option parsing, transactional generation,
generation-time error-message support, and output coordination.

Optional subcommand modules are registered with Ruby autoloads. Dispatch
resolves and extends only the current CLI instance with the module selected by
the first argument. This keeps concurrent CLI instances independent while
preserving every named CLI module constant. The `errors` subcommand is
separate from the small generation-time `--messages` adapter. Watch support
is activated only after `--watch` is parsed.

Each optional CLI source requires its own subsystem entry point. The LSP entry
point likewise requires only version, error, and frontend support instead of
recursively requiring the umbrella library. Optional report, RBS,
action-shadow, visualization, railroad, and error-message generators load
when their corresponding generation option is used.

Ordinary generation is the default eligibility case. Selecting a subcommand
or an optional generation output is the explicit compatibility gate that
loads its implementation. Subprocess tests inspect loaded features after a
plain require, ordinary generation, and selected-subcommand dispatch. Existing
CLI integration tests remain the behavioral contract for every option and
subcommand.

This is solely a Ruby load-boundary change. Grammar IR, Automaton IR, generated
Ruby bytes, semantic actions, runtime behavior, parser table format, and table
ABI do not change.

## Consequences

- Cold generation does not parse or execute unrelated CLI implementation
  files.
- `require "ibex"` retains its complete public library behavior, while
  `require "ibex/cli"` keeps optional CLI constants available through
  autoload.
- A direct subsystem dependency is visible beside each CLI feature instead of
  being supplied by umbrella ordering.
- The first invocation of an optional feature pays its require cost; later
  invocations reuse Ruby's loaded feature.
- Future subcommands must be added to the dispatch/autoload map and declare
  their own subsystem dependencies.
