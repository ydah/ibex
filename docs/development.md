# Development and quality checks

This document describes contributor workflow and repository quality gates.
These practices verify the implementation but are not implementation
architecture decisions.

## Default checks

Install the default development dependencies and run the unit, integration,
documentation, and style suite:

```sh
bundle install
bundle exec rake
```

Additional repository checks are:

```sh
bundle exec rake frontend:check
bundle exec rake grammar:test
bundle exec rake quality:error_ux
npm ci
npm run test:site
actionlint
zizmor .
```

CI runs the supported Ruby matrix separately from optional experimental Ruby
implementations. Workflow and dependency-update configuration are authoritative
for the current matrix, schedules, permissions, and pinned action versions.

## Browser site and API documentation

Install the locked browser dependencies and build the same self-hosted site
bundle exercised in CI:

```sh
npm ci
npm run test:site
BUNDLE_GEMFILE=gemfiles/docs.Gemfile bundle exec yard doc
```

`tool/build_site.rb`, the YARD configuration, and
`.github/workflows/pages.yml` are authoritative for documentation inputs,
build versions, artifact retention, deployment permissions, and the protected
Pages environment. Publication runs from `main`; pull requests validate the
site without receiving deployment credentials.

Changing those operational settings does not require an implementation ADR.
A change to the shipped browser analyzer's worker isolation, execution limits,
or Ruby/JavaScript data boundary does.

## Self-hosted frontend

`lib/ibex/frontend/grammar.y` is the production grammar. Regenerate its
committed parser after changing the frontend language:

```sh
bundle exec rake frontend:generate
bundle exec rake frontend:check
bundle exec ruby -Itest test/frontend/self_host_test.rb
```

`lib/ibex/frontend/shadow_grammar.y` independently describes the same language
using parameterized and inline rules. Tests build it through the bootstrap
frontend and compare its location-preserving AST with the production parser.
The shadow source must change with the canonical grammar, but it never replaces
the committed production parser.

## RBS and Steep

The optional type toolchain is isolated in `gemfiles/Gemfile`. Regenerate the
committed RBS tree, validate it, type-check the library, and refresh the
documented statistics with:

```sh
BUNDLE_GEMFILE=gemfiles/Gemfile bundle install
BUNDLE_GEMFILE=gemfiles/Gemfile ruby -e '
  sources = Dir.glob("lib/**/*.rb").sort
  exec("bundle", "exec", "rbs-inline", "--opt-out", "--base=lib", "--output=sig", *sources)
'
BUNDLE_GEMFILE=gemfiles/Gemfile bundle exec rbs -r digest -r json -r optparse -r tempfile -r timeout -r tmpdir -r uri -I sig validate
BUNDLE_GEMFILE=gemfiles/Gemfile bundle exec steep check
BUNDLE_GEMFILE=gemfiles/Gemfile bundle exec ruby tool/type_stats.rb --write
```

CI generates signatures into a clean temporary directory and compares the
complete tree, so both missing and stale signature files fail.

## Bounded mutation testing

Mutation analysis is intentionally separate from the default dependencies:

```sh
BUNDLE_GEMFILE=gemfiles/mutation.Gemfile bundle install
BUNDLE_GEMFILE=gemfiles/mutation.Gemfile bundle exec rake quality:mutation
```

The job uses MRI 4.0, two workers, a ten-minute job budget, and the focused
`Ibex::Tables::Compact#initialize` matcher. `TablesTest` owns the mutation
coverage declaration. The mutation environment declares open-source usage and
applies a one-second timeout to each deterministic mutation. Expanding the
subject requires an explicit test owner, no surviving non-equivalent mutations,
and a measured duration within the same bounded job.

The isolated Gemfile keeps the mutation tool's Ruby floor and dependencies
from changing the library's supported runtime matrix.

## Benchmarks and evidence

Performance observations are not ordinary CI timing thresholds. Follow the
[benchmark guide](../benchmark/README.md) for workload identities, formal
comparison commands, environment matching, artifact validation, and
append-only result history.

The external-grammar profiler has its own exact-version tool bundle:

```sh
BUNDLE_GEMFILE=gemfiles/profile.Gemfile bundle install
BUNDLE_GEMFILE=gemfiles/profile.Gemfile bundle exec ruby benchmark/public_profile.rb --help
```

Its output is diagnostic-only and must remain outside `benchmark/results/`.
Use it to locate costs, then repeat the uninstrumented public comparison to
produce reviewable performance evidence.

The versioned error-experience snapshot and its review procedure live in
[`docs/error-ux.md`](error-ux.md).
