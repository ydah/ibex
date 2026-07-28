# ADR 0015: Isolate browser analysis in a replaceable worker

- Status: Accepted
- Date: 2026-07-28

## Context

Ruby running through WebAssembly can consume substantial CPU and memory.
Running grammar analysis on the main browser thread would let a pathological
input freeze the interface, and interpolating grammar text into Ruby source
would create an unnecessary execution boundary.

## Decision

The Ruby VM and grammar-analysis pipeline run in a dedicated module worker.
The main thread owns the timeout and replaces the worker on expiry. Input,
diagnostic, conflict, and search sizes are bounded. Grammar bytes cross the
JavaScript/Ruby boundary as data and semantic action bodies are never
evaluated.

The worker returns serialized analysis results only. Browser assets are
self-hosted under a restrictive Content Security Policy, and no submitted
grammar is sent to or stored by an application server.

## Consequences

- Pathological analysis cannot retain Ruby state after worker replacement and
  cannot block the main thread indefinitely.
- Worker termination is the isolation boundary, not a claim that WebAssembly
  is a security sandbox.
- Browser support depends on Web Workers, WebAssembly, module scripts, and the
  shipped Ruby VM asset.
