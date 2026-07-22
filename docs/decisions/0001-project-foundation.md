# 0001: Project foundation

- Status: Accepted
- Date: 2026-07-22

## Context

The repository was created from a generic gem template using RSpec and Ruby 3.2. The project instructions require Ruby 3.0,
Minitest, zero runtime dependencies, and a phase-oriented directory structure.

## Decision

Use Minitest and RuboCop as development-only dependencies, support Ruby 3.0 and later, and expose `exe/ibex` as the gem
executable. Modules are added when their phase gains behavior instead of committing empty placeholders.

## Consequences

The default task enforces both tests and lint. The gem has no runtime dependencies, while development setup uses Bundler.
