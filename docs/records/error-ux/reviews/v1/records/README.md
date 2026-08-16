# Independent error UX review records v1

Published third-party payload JSON records belong in this directory and are
registered by path, SHA-256, immutable blob/raw identity, source-owner and
publisher logins, and manual import-vetting fields in
[`error-ux-review-status-v1.json`](../../../../../evidence/error-ux-review-status-v1.json).
The directory intentionally contains no JSON while R001 is on HOLD.

Import the exact bytes fetched from the reviewer's full-SHA GitHub blob. Do not
normalize line endings, formatting, wording, labels, rationales, or disagreement
notes. Publication metadata is stored only in the separate status registry so
the payload has no self-referential URL. The quality tasks reject unregistered
files, drafts, rostered-maintainer reviews, mutable or noncanonical publication
links, incomplete structured consent, placeholders, identity drift, and
incomplete case sets.

The source owner, commit API author, publisher, and reviewer logins must agree
case-insensitively. That check records control of the named GitHub namespace and
GitHub account metadata; it is not a cryptographic identity proof or signature.

See the [v1 rubric](../../../../../evidence/error-ux-review-rubric-v1.md) for the independent
review and publication workflow.
