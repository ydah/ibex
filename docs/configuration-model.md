---
title: Configuration model
description: Decide which parser settings belong to grammar source and which belong to an invocation.
---

# Configuration model

Ibex keeps reproducible grammar intent in the grammar and keeps environment or
review choices at the invocation boundary. This separation prevents a build
flag from silently changing a source-owned parser contract.

## Grammar-owned settings

Declare settings in an extended grammar when every consumer should observe the
same choice:

```text
class ExampleParser
pragma extended
parser
  algorithm ielr
  entries isolated
end
```

The current grammar-owned parser block supports `slr`, `lalr`, `ielr`, or
`lr1` construction and `shared` or `isolated` entry handling. The declaration
is part of normalized Grammar IR and is visible in generated reports.

## Invocation-owned settings

Keep these choices at the CLI or API call site because they describe a local
operation rather than the grammar's meaning:

- output path and embedded-runtime selection (`-o`, `-E`);
- table representation and diagnostic format;
- warnings, verification strictness, resource budgets, and report output;
- a temporary analysis algorithm used for comparison or investigation; and
- external command execution for explicitly unsafe fuzz or reduction workflows.

An invocation may select an analysis algorithm, but it must report that the
selection is noncanonical when it differs from the grammar declaration. A
conflicting canonical selection is rejected at the declaration location.

## Review checklist

When adding a setting, ask:

1. Would two independent users of the same grammar need the same value? If so,
   it is grammar-owned.
2. Is the value about this run, host, output, or evidence capture? If so, it is
   invocation-owned.
3. Does changing it alter generated parser behavior, persisted IR, or runtime
   ABI? Update the relevant schema, fixture, maturity entry, and migration note.
4. Is the setting opt-in? Keep the compatible default unchanged and document
   the activation boundary next to the option.

See the [stability policy](stability.md), [grammar reference](grammar-reference.md),
and [development guide](development.md) for contract and verification rules.
