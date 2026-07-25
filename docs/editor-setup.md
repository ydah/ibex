# Editor setup

Ibex ships an LSP 3.17 server for grammar files:

```sh
ibex lsp --stdio
```

Configure an editor language client to start that command for `.y` files and pass the project directory as `rootUri` or an
initial `workspaceFolders` entry. The server uses standard Content-Length framing on stdin/stdout. Do not wrap it with a command
that writes banners or logs to stdout; Ibex writes its own logs to stderr.

The server negotiates UTF-16 positions and full-document text synchronization. It provides:

- bounded parse and include diagnostics, including unsaved included fragments;
- definition and references for rules, formal parameters, terminals, and include targets;
- guarded cross-file prepare-rename and rename; and
- hover for rule signatures/documentation, terminal metadata/precedence, and include targets.

Only local `file:` URIs below the initialized workspace roots are accepted. Symlink escapes, traversal, remote authorities,
query/fragment URI components, and ambiguous encoded separators are rejected. Open buffers override disk until `didClose`;
closing first clears the buffer diagnostics and then restores the disk snapshot.

For a generic editor configuration, use command `ibex`, arguments `lsp --stdio`, language id `ibex`, and file pattern `*.y`.
Ibex never executes semantic actions or `header`, `inner`, or `footer` code while serving editor requests.
