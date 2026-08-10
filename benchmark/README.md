# Whole-builder benchmark

Comparative measurements are publishable claims only when they follow the
[comparison policy](../docs/comparison-policy.md) and have a validated entry in
[`docs/claims.yml`](../docs/claims.yml). Benchmark output alone is not a claim:
the registry also fixes its wording, subjects, corpus, environment, unsupported
semantics, evidence, limitations, and review conditions. Run
`bundle exec rake quality:comparative_claims` before publishing comparative
wording.

Capture the pre-Red/Green CST construction baseline with:

```sh
bundle exec ruby benchmark/cst.rb \
  --rules 25 \
  --iterations 2000 \
  --runs 5 \
  --seed 12345 \
  --output benchmark/results/cst/YYYY-MM-DD-REV-ruby-VERSION-PLATFORM.json
```

The CST probe compares the same generated lexer and grammar with and without
`pragma cst`. Version 5 alternates measurement order and reports the median of
`--runs` samples, total allocated objects, and the ratio between Green
occurrences and distinct Green object identities. A separate TracePoint probe
counts current `GreenNode`/`GreenToken` constructor calls. The report also
measures one fixed recovery workload through plain and current Red/Green CST
paths. Version-4 and earlier artifacts retain their historical legacy-CST
comparisons, but the executable benchmark no longer constructs the removed
tree model. Identity and construction probes complement rather than replace
the process-wide allocation count. Timings and allocations are local
observations, not CI thresholds. Reviewed observations are append-only under
`benchmark/results/cst/`.

The current-only version-5 observation is
`2026-07-28-current-only-ruby-4.0.0-arm64-darwin24.json`. It records the same
25-terminal, 2,000-parse, five-run workload after removal of the obsolete CST
path. Historical version-4 artifacts remain unchanged.

Compare syntax-only Stage A, Blender Stage B, and fresh syntax sessions with:

```sh
bundle exec ruby benchmark/cst_incremental.rb \
  --terms 100 \
  --iterations 100 \
  --seed 20260727 \
  --output benchmark/results/cst/YYYY-MM-DD-blender-ruby-VERSION-PLATFORM.json
```

The report measures one-byte edits near the beginning, middle, and end. It
records relexer scan counts, Green token reuse, directly reused descendants,
allocations, and Stage-B speedups over both controls. Compare wall-clock values
only within an identical Ruby, platform, workload, and revision; the fixed-seed
incremental-versus-batch property tests remain the correctness authority.

Run the deterministic 501-production scale construction benchmark with:

```sh
benchmark/scale.rb --rules 500 --iterations 3
benchmark/scale.rb --rules 500 --iterations 3 --json
```

The source is generated in memory as one start production followed by 500
recursive productions, matching the large compatibility probe. The report
publishes the direct-LALR construction and final state counts, complete-build
time range, compact generated size, conflicts, environment, and reproducibility
digests. It is a deliberately synthetic breadth/depth stress case; the
representative benchmark below remains the realistic control-flow workload.

The opt-in direct IELR construction probe compares the experimental direct and
canonical-partition strategies over the paper fixtures and gallery grammars:

```sh
bundle exec ruby benchmark/ielr.rb --wall-seconds=30 --output=tmp/ielr-benchmark.json
```

The report follows `schema/ielr-benchmark-v1.schema.json`. Structural metrics,
conflicts, and source digests are deterministic; elapsed time is host-bound
observation only. The corresponding CI-friendly quality gate is:

```sh
bundle exec rake quality:direct_ielr_decision
```

It runs the bounded direct-IELR fuzz probe, checks both strategies are present
for every benchmark workload, and verifies the existing I001 NO-GO dossier. A
passing probe is bounded evidence, not a semantic adequacy proof or a release
promotion.

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
bundle exec ruby benchmark/verify.rb benchmark/results/v2/2026-08-10-cbb20aa9897a-ruby-4.0.0-arm64-darwin24.json
```

The current v2 observation records direct LALR construction: 250 intermediate
construction states and 250 final states. Its deterministic source, input, IR,
and table structure match the preceding v2 artifact, as do the source, input,
and runtime-result digests. The current-only IR and runtime surface changed the
Grammar/Automaton IR and generated Ruby digests without changing the measured
state or table counts. The
canonical-merge v1 baseline retained 1,294 intermediate states. Grammar/Automaton IR, tables, generated outputs, and runtime
result remain byte-identical between the direct and retained reference
strategies within one revision. Earlier observations remain unchanged under the append-only
history contract.

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

The compatibility-preserving generated `case` candidate has a separate
optimization experiment. It retains the parser tables for debugging, repair,
and public table inspection, injects only the runtime lookup override, verifies
result/Automaton digests, and runs every observation in a fresh process:

```sh
benchmark/optimization_candidates.rb --runs 5 --warmup 100 --iterations 1000 --output tmp/optimization.json
```

Run the same command on at least two supported MRI versions before changing the optimization decision. The report also records
the representative grammar's unit-production surface; it does not rewrite production identities.

The reviewed MRI 3.4.9 and 4.0.0 reports for revision `05dc61bdb5d0` are committed under
`benchmark/results/optimization/`. Both reject the case candidate: its runtime median improves by more than 15%, but retaining
the authoritative tables makes generated source 198% larger. Production identities remain observable runtime data, so the
experiment does not apply chain elimination.

## Racc comparison control

Run the repository-owned, process-isolated comparison with the Racc version
installed for the same Ruby:

```sh
bundle exec ruby benchmark/comparison.rb \
  --runs 10 \
  --warmup 50 \
  --runtime-iterations 250 \
  --behavior-probe-iterations 5 \
  --bootstrap-samples 10000 \
  --expected-racc-backend ruby \
  --output tmp/performance-comparison.json
```

Run a separate command under `ruby --yjit` when YJIT evidence is needed; never
combine it with the default YJIT-off samples. The report distinguishes cold CLI
generation from warm generated-parser execution, lexer-inclusive from
pretokenized input, and parser reuse from new-instance parsing. Implementations
alternate first position across isolated runs.

Cold generation is an end-to-end CLI observation under the formal command
template. The template's explicit generation options leave the default
algorithm and requested diagnostic path intact.
Generator-core or stage-level profiles may isolate that work for diagnosis,
but they are not comparable substitutes for the formal cold series and must
not disable the default diagnostic path.

Formal evidence compares Ibex's Pure Ruby runtime with Racc's Ruby runtime.
Each isolated Racc worker selects that parsing routine through Racc's
`Racc_No_Extensions` switch and verifies `racc_runtime_type` before reporting
the observation. The command rejects mixed or unexpected backend observations;
use `--expected-racc-backend native` only for a separately labelled diagnostic
run.
Every worker must also report the same effective YJIT state and `RUBYOPT`
identity as the parent. The artifact redacts `RUBYOPT` values and paths while
retaining presence, byte count, sanitized option names, and a SHA-256 identity.

Runtime series include elapsed time and allocated-object counts per parse.
Generation series include elapsed time and generated byte size. Every series
reports a median, median absolute deviation, range, and deterministic bootstrap
95% interval for the Ibex-to-Racc median ratio. The target flag requires the
interval's upper bound to be no greater than `1.0`; it is review evidence, not
a CI timing threshold or a v1.0 release condition. The v1.0 condition is to
publish the measured values with their complete comparison conditions. A
future gate may compare only relative regression against an observation with
an identical environment and configuration.

An untimed bounded probe follows each measured runtime region. Its sequence
digest covers every repeated result and must match across lexer-inclusive and
pretokenized drivers, with both reused and newly allocated parser instances.
The report also distinguishes tracked and untracked dirtiness and records the
kernel release plus a best-effort CPU model. The assembled JSON is schema
validated before any output is written.

The comparison worker derives an uncommitted grammar with the same EOF shape
for both runtimes and a pretokenized driver. The artifact records both grammar
digests and the adaptation name, while the existing representative benchmark
and append-only history remain unchanged. Result and behavior digests must
agree across both implementations and all four runtime scenarios. The report
follows `schema/performance-comparison-v1.schema.json`. This owned workload is
the control experiment; it does not replace the fixed-revision public
workloads below.

## Fixed-revision public grammar comparison

The formal release-evidence workloads for Namae, BCDice's command parser, and
Nokogiri CSS have an executable manifest in
`benchmark/public_workloads.json`. Their exact source and license evidence,
structural counts, known problems, and eligibility scopes are also bound in the
[public workload registry](../docs/workloads.md). Prepare separate, clean
checkouts without running code from them:

```sh
git clone https://github.com/berkmancenter/namae.git /path/to/namae
git -C /path/to/namae checkout --detach d33875aaf1fc420a8dfe946a3b29cc3e19710061
git clone https://github.com/bcdice/BCDice.git /path/to/bcdice
git -C /path/to/bcdice checkout --detach 21b4a03789bf2080ad41aaf31299b609ee7bda86
git clone https://github.com/sparklemotion/nokogiri.git /path/to/nokogiri
git -C /path/to/nokogiri checkout --detach 04a4c29c6a605ad40a78f4ce343ced0832a1805c
```

Review those revisions before continuing. The benchmark loads generated
parsers and selected application support files, so running it executes
third-party code from every supplied checkout.

None of these three revisions tracks `Gemfile.lock`; lockfiles found in older
diagnostic directories were ignored local files and are not reproducible
inputs. The manifest therefore identifies each tracked `Gemfile` as the
dependency definition. The harness does not install or activate each
project's bundle: both implementations run under the root Ruby and Racc
environment recorded in the artifact.

Run a formal YJIT-off comparison with:

```sh
bundle exec ruby benchmark/public_comparison.rb \
  --checkout namae=/path/to/namae \
  --checkout bcdice_command=/path/to/bcdice \
  --checkout nokogiri_css=/path/to/nokogiri \
  --runs 10 \
  --warmup 50 \
  --runtime-iterations 250 \
  --behavior-probe-iterations 5 \
  --bootstrap-samples 10000 \
  --expected-racc-backend ruby \
  --output tmp/public-performance-comparison.json
```

The command verifies each full revision, origin, expected grammar SHA-256, and
expected production/state/token/conflict metrics, rejects a dirty Ibex root
or dirty public checkout, requires the dependency definition to be tracked at
`HEAD`, and records grammar and dependency-definition digests plus the
committed `lib/` Git tree object ID, status, workload, and manifest digests.
It repeats the complete checkout verification after collecting observations
and rejects any metadata change before emitting a report. The Git tree
identity avoids opening external generated parser outputs.

The Ibex root receives the same before/after boundary: its revision plus
aggregate, tracked, and untracked dirty state must remain identical, and both
samples must be clean for formal evidence. The verified final environment is
the one embedded in the report.

Workers alternate implementation order and reject effective YJIT, `RUBYOPT`,
backend, result, repeated-result-sequence, or observation-count mismatches.
Formal reports require Racc's Ruby backend and always contain exactly the
configured count of at least ten isolated processes per implementation and
scenario. `--smoke --allow-dirty-checkouts` exists only to diagnose local
checkouts; its artifact is labelled `diagnostic_smoke` and is not release
evidence. Native-Racc measurements additionally require `--smoke` and remain
diagnostic rather than release evidence.

Public runtime scenarios are lexer-inclusive and cover parser reuse and a new
parser for every parse. Pretokenized/core timing remains in the repository-owned
control above: injecting token drivers into third-party grammars would change
the public code being measured. Timing is review evidence and is not an
ordinary CI pass/fail threshold. Public reports follow
`schema/public-performance-comparison-v1.schema.json`.

### Diagnostic profiles for public grammars

When a formal row is slower than Racc, collect Ibex-only wall-clock profiles
against the same manifest revisions before changing the implementation. The
root development bundle includes the exact-version profiler.

Then profile cold generation and both lexer-inclusive runtime lifecycles for
all three checkouts:

```sh
bundle exec ruby benchmark/public_profile.rb \
  --checkout namae=/path/to/namae \
  --checkout bcdice_command=/path/to/bcdice \
  --checkout nokogiri_css=/path/to/nokogiri \
  --runs 1 \
  --warmup 50 \
  --runtime-iterations 10000 \
  --output tmp/public-performance-profile.json
```

Each scenario and run starts a fresh child process. Cold generation begins
sampling before the Ibex CLI is loaded. Runtime setup uses the exact formal
Ibex generation command, loads the resulting public parser, completes warm-up
outside the profiler, and samples the same lexer-inclusive workload loop as
the formal comparison. A short untimed result-sequence probe follows the
sampled region so lifecycle and run mismatches fail before publication.

The JSON report records the exact formal generation and worker commands
separately from each instrumented command. It also writes StackProf raw dumps
to a sibling `.profiles/` directory. Reported frame paths are portable, while
raw dumps remain machine-local diagnostics.

These profiles include profiler overhead and are never timing evidence. The
schema fixes `evidence_kind` to `diagnostic_profile`, `formal_evidence` to
`false`, and `timing_comparable` to `false`; the command also rejects outputs
under `benchmark/results/`. `--allow-dirty` is available only for local
diagnosis and is recorded in the report.

Use `--interval-usec` and `--top-frames` to change profile resolution. The
10,000-workload runtime default is intentionally longer than the formal timing
default so a 1 ms wall-clock sampler gathers useful stacks. Increase it when a
profile still contains too few samples. After optimizing a dominant stack,
rerun the uninstrumented formal public comparison above on the same Ruby, YJIT
mode, checkouts, and clean revision. Only that repeated formal report can
refresh the ratios and establish a reviewable relative baseline.
