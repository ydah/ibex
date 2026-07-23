# 0027: Keep build integration explicit and dependency-scoped

- Status: Accepted
- Date: 2026-07-23

## Context

Applications commonly generate parsers from a `Rakefile`. Shelling out works, but repeats output-path conventions and makes the
grammar-to-parser dependency less visible to Rake. Requiring Rake from the main `ibex` entry point would also violate the runtime's
dependency-free boundary.

## Decision

`require "ibex/rake_task"` provides `Ibex::RakeTask`. It defines a file task from one grammar source to one generated Ruby parser
and can optionally expose a named aggregate task. Generation calls the public CLI coordinator in-process and forwards an explicit
array of options.

The task integration is opt-in. The main library and generated parsers do not require Rake, and the gem does not add a runtime
dependency. Applications using this adapter must include Rake in their own development or build dependencies.

## Consequences

Rake can skip current generated parsers using ordinary timestamp semantics and applications can compose parser generation with
their existing tasks. Projects that do not use Rake pay no load-time or dependency cost.
