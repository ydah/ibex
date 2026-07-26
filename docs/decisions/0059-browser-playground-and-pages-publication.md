# 0059: Publish a worker-isolated browser playground and API reference

- Status: Accepted
- Date: 2026-07-26
- Supersedes: the ruby.wasm and Pages/YARD entry boundaries in ADR 0024

## Context

Ibex's Pure Ruby implementation can run in a browser, but a public playground introduces a large executable asset, untrusted
grammar text, a long-running analysis risk, and a second dependency ecosystem. Publishing generated API documentation also
requires an exact source boundary, a deployment owner, and tightly scoped repository permissions.

ADR 0038 supplies representative benchmark evidence. The README, checked RBS, versioned JSON schemas, and public Ruby
visibility now identify the supported interface. Repository maintainers own publication from `main`; deployments are not
accepted from pull requests or arbitrary branches.

## Decision

Publish one static project site at `https://ydah.github.io/ibex/`:

- a landing page and browser playground built from `site/`;
- a YARD API reference generated from public and protected objects in `lib/**/*.rb`, excluding the generated frontend parser;
- one GitHub Pages artifact with a one-day retention period, deployed through the protected `github-pages` environment.

YARD's source boundary is documentation, not an expansion of compatibility guarantees. The stable contract remains the APIs
described by the README and checked signatures plus the versioned schemas. CLI implementation details and otherwise-undocumented
public helper objects may appear for discoverability without gaining a separate stability promise.

The playground uses the exact locked `@ruby/4.0-wasm-wasi` package and bundles it with esbuild. Assets, styles, scripts, and fonts
are self-hosted; Dependabot checks the npm lockfile weekly. A restrictive Content Security Policy allows only same-origin assets
and WebAssembly compilation.

The Ruby VM and all grammar analysis run in a dedicated module worker. The main thread terminates and replaces that worker after
15 seconds. Input is limited to 100,000 bytes, frontend diagnostics to 20, parameter and inline expansion retain their library
bounds, displayed conflicts are limited to 100, and counterexample search retains the 32-token and 50,000-configuration bounds.
Grammar text crosses the JavaScript/Ruby boundary as UTF-8 hex decoded by `Array#pack`; it is never interpolated into Ruby source.
Semantic action bodies remain opaque frontend data and are never evaluated.

The interface has explicit labels, keyboard submission, visible focus, live status text, at least 44-pixel controls, responsive
single-column behavior, and reduced-motion handling. Analysis results can be downloaded as Automaton IR without a server
round-trip.

The Pages workflow has read-only contents permission while building. Only the deployment job receives `pages: write` and
`id-token: write`. All third-party actions are pinned to full commit hashes. CI builds the site, boots the actual ruby.wasm image,
and analyzes a grammar whose action contains Ruby interpolation syntax to prove the bridge and analyzer do not execute it.

## Consequences

- The playground and API reference are reproducible from locked Ruby, npm, and action dependencies.
- A roughly 31 MiB WebAssembly asset is paid once by visitors and remains cacheable; no application server or submitted-source
  storage exists.
- Pull requests validate the complete browser bundle without receiving deployment credentials.
- Publishing is intentionally coupled to a green build from `main`; repository maintainers own rollback through a prior commit
  or workflow rerun.
- Browser support follows ruby.wasm, Web Workers, WebAssembly, module scripts, and the declared Content Security Policy.
