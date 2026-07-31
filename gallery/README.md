# Grammar gallery

The gallery is a small correctness and diagnostics corpus, not a language
implementation claim. Every grammar is self-authored, has explicit provenance
and licensing, contains accepted and rejected inputs, and commits the expected
state/conflict counts for every supported construction algorithm. Each
rejected input is paired with a reviewed message-catalog ID, unexpected token,
position, and expected-token set; accepting it or changing that diagnostic
fails the gallery gate.

Run `bundle exec rake gallery:build` to build both table formats and execute
the corpora. Run `bundle exec rake gallery:conflicts` to check structural
metrics.
