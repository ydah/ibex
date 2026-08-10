# Contributing to Ibex

Thank you for helping improve Ibex. Start with a focused issue or pull
request and describe the user task it changes. The [project site](https://ydah.github.io/ibex/project/)
has the current status, roadmap, and contribution links.

## Before changing code

1. Read the relevant guide in [`docs/`](docs/) and any linked architecture decision record.
2. Check the maturity and stability policy before changing a public or Preview surface.
3. Keep grammar-owned configuration separate from invocation-owned options.
4. Do not commit generated files, `.idea/` material, local bundles, or benchmark output unless a repository check explicitly requires the artifact.

## Local checks

Use the complete development bundle for the normal gate:

```sh
bundle install
bundle exec rake
npm ci
npm run test:site
```

For a focused change, run the smallest relevant test first, then the complete
gate before requesting review. Changes to the frontend grammar must regenerate
its parser and pass `bundle exec rake frontend:check`. Changes to public
contracts also need schema, fixture, documentation, and generated-signature
review.

## Pull requests

- Explain the behavior and user-facing documentation change.
- State whether the change affects Stable, Preview, or Experimental surfaces.
- Include regression coverage and the commands you ran.
- Call out runtime ABI, generated output, persisted IR, and security-boundary impact.
- Keep commits focused; do not add author trailers or agent identifiers to commit messages.

Please do not include secrets, private grammar source, or customer data in an
issue or pull request. Use the private security process for vulnerabilities.
