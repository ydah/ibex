# External grammar policy

The committed gallery contains only grammars written for this repository.
Third-party grammar files are not copied into releases, fixtures, or generated
artifacts.

An optional external compatibility job may download a grammar at a pinned
revision after recording its source URL and license. It may publish only Ibex
diagnostics and aggregate measurements, never the downloaded source. Such a
job is evidence, not a package input, and must run without inspecting the
other parser generator's implementation or generated source.
