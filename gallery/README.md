# Grammar gallery

The gallery is a small correctness and diagnostics corpus, not a language
implementation claim. Every grammar is self-authored, has explicit provenance
and licensing, contains accepted and rejected inputs, and commits the expected
state/conflict counts for every supported construction algorithm.

Run `bundle exec rake gallery:build` to build both table formats and execute
the corpora. Run `bundle exec rake gallery:conflicts` to check structural
metrics.
