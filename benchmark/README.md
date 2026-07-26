# Whole-builder benchmark

Run the reproducible parse-to-codegen and runtime benchmark from the repository root:

```sh
benchmark/pipeline.rb --iterations 1 --runtime-iterations 10 --seed 12345 --output tmp/benchmark-current.json
benchmark/pipeline.rb --iterations 1 --runtime-iterations 10 --seed 12345 --json
```

The first command prints the readable report and always writes a JSON artifact to `--output`; `--json` changes stdout to JSON.
For a lower-noise local observation, increase both iteration counts only after the smoke command succeeds.

`benchmark/grammars/representative.y` is a self-authored, conflict-free C-like grammar with 139 productions. Its matching input
exercises declarations, generic types, functions, control flow, pattern matching, postfix expressions, and both generated table
formats. The fixed seed adds a deterministic workload declaration.

Current JSON output follows `schema/benchmark-v2.schema.json` and carries the `ibex_benchmark` discriminator with
`schema_version: 2`. Immutable historical documents continue to follow `schema/benchmark-v1.schema.json`.
It records:

- generation and per-stage wall-clock averages;
- plain and compact generated-parser runtime averages;
- process peak RSS when `/proc` or `ps` exposes it;
- productions, construction strategy, intermediate construction states, and final parser states;
- physical table cells and deterministic serialized bytes for both formats;
- generated Ruby bytes; and
- source, input, IR, table, output, runtime-result, and aggregate SHA-256 digests.

Wall-clock and RSS values are observations only and never pass/fail thresholds. Structural counts and digests are deterministic:
identical iterations fail immediately if they diverge. `Ibex::LALR::Builder#metrics` exposes the strategy, construction/final
counts, and a canonical count only when that collection was actually built.

Committed v1 history lives under `benchmark/results/v1/`; new reviewed results live under the directory matching their schema
version. Filenames describe the measured revision and environment rather than a
portable speed score. Every artifact contains the complete Ruby, Ibex, OS, CPU, and processor metadata needed to interpret its
observations. The initial `representative-ruby-4.0.0-arm64-darwin24.json` baseline predates the revision-naming rule and remains
unchanged; every new entry follows the reviewed naming contract below.
Validate a baseline and rebuild its deterministic projection with:

```sh
bundle exec ruby benchmark/verify.rb benchmark/results/v1/2026-07-25-706e9e3cd90f-ruby-4.0.0-arm64-darwin24.json
```

The current dated observation follows the table ABI v3 change. Relative to
`2026-07-25-c55ff20e58e6-ruby-4.0.0-arm64-darwin24.json`, grammar structure, Grammar/Automaton IR, tables, and the runtime result
are unchanged; only the plain and compact generated-output digests (and their aggregate artifact digest) changed. The earlier
observations remain unchanged under the append-only history contract.

CI performs this schema and structure check on every change. The scheduled and manually dispatched workflow additionally runs
three complete builds and 1,000 parses per format. It writes
`ibex-benchmark-<full-revision>-ruby-<version>-<runner-os>-<runner-arch>.json` and uploads it under the safe, run-scoped artifact
name `ibex-benchmark-<run-id>-<run-attempt>` for 30 days.

To append a reviewed result:

1. Download the workflow artifact for the exact measured revision and check out that revision.
2. Run `bundle exec ruby benchmark/verify.rb path/to/downloaded.json`; this validates both the downloaded schema and a freshly
   generated document before comparing deterministic structure and digests.
3. Compare performance only with entries whose complete `environment` and `configuration` objects are identical. Different Ruby,
   OS, CPU, processor count, seed, workload, or iteration counts start a separate series.
4. Rename the accepted file to
   `YYYY-MM-DD-<revision12>-ruby-<version>-<ruby-platform>.json`, add it under `benchmark/results/v<schema>/`, and review the environment,
   observations, structure, and digests in the change.

History is append-only: never replace or delete an earlier observation to make a new result appear better. Rejected or expired CI
artifacts are not part of the repository history.

Run the self-authored calculator, JSON, INI, and tiny-language grammars across
plain/compact tables and mapped/direct semantic actions with:

```sh
benchmark/examples.rb --generation-iterations 3 --runtime-iterations 100
```

This second benchmark measures a complete grammar-to-Ruby build and repeated parses for every smaller example variant. `--json`
emits results suitable for local comparison.

The runtime-event instrumentation boundary has a separate construction-count probe with no timing threshold:

```sh
bundle exec ruby benchmark/runtime_events.rb
```

Its `without_observer` counts must remain zero; `with_observer` reports event, semantic-summary, and location-summary
construction so reviews can detect accidental work on the dormant path.
