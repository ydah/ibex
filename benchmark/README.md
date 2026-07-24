# Whole-builder benchmark

Run the reproducible parse-to-codegen and runtime benchmark from the repository root:

```sh
benchmark/pipeline.rb --iterations 3 --runtime-iterations 100 --seed 12345
benchmark/pipeline.rb --iterations 1 --runtime-iterations 10 --seed 12345 --json
```

`benchmark/grammars/representative.y` is a self-authored, conflict-free C-like grammar with 139 productions. Its matching input
exercises declarations, generic types, functions, control flow, pattern matching, postfix expressions, and both generated table
formats. The fixed seed adds a deterministic workload declaration.

JSON output follows `schema/benchmark-v1.schema.json` and carries the `ibex_benchmark` discriminator with `schema_version: 1`.
It records:

- generation and per-stage wall-clock averages;
- plain and compact generated-parser runtime averages;
- process peak RSS when `/proc` or `ps` exposes it;
- productions, canonical intermediate states, and final LALR states;
- physical table cells and deterministic serialized bytes for both formats;
- generated Ruby bytes; and
- source, input, IR, table, output, runtime-result, and aggregate SHA-256 digests.

Wall-clock and RSS values are observations only and never pass/fail thresholds. Structural counts and digests are deterministic:
identical iterations fail immediately if they diverge. `Ibex::LALR::Builder#metrics` exposes the two state counts as a frozen
diagnostic value after `build`.

Committed history lives under `benchmark/results/v1/`; filenames describe the measurement environment rather than a portable
speed score. Every artifact contains the complete Ruby, Ibex, OS, CPU, and processor metadata needed to interpret its observations.
Validate a baseline and rebuild its deterministic projection with:

```sh
bundle exec ruby benchmark/verify.rb benchmark/results/v1/representative-ruby-4.0.0-arm64-darwin24.json
```

CI performs this schema and structure check on every change. The scheduled and manually dispatched workflow additionally runs
three complete builds and 1,000 parses per format, printing the observational result to the job log.

Run the self-authored calculator, JSON, INI, and tiny-language grammars across
plain/compact tables and mapped/direct semantic actions with:

```sh
benchmark/examples.rb --generation-iterations 3 --runtime-iterations 100
```

This second benchmark measures a complete grammar-to-Ruby build and repeated parses for every smaller example variant. `--json`
emits results suitable for local comparison.
