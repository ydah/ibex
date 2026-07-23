# ADR 0022: Compile mapped semantic-action methods once

- Status: Accepted
- Date: 2026-07-23
- Supersedes: [ADR 0007](0007-generated-action-lines.md)

## Context

ADR 0007 preserves grammar filenames and line numbers by calling
`eval(action_code, binding, file, line)` from the generated reduction method.
That recompiles the same opaque Ruby source on every reduction. Semantic
actions are commonly the hottest part of a generated parser, so repeated
compilation imposes a large default-mode cost that is unrelated to LR table
dispatch.

The replacement must preserve the existing contracts:

- the first line of action source keeps its original grammar line;
- multiline actions, heredocs, inline-action stack context, named references,
  `result_var`, and `no_result_var` retain their behavior;
- generated action methods remain private;
- `-l` continues to emit inspectable method bodies at generated-file lines;
- embedded and runtime-requiring output behave identically.

Action bodies remain opaque Ruby. This change must not imply that Ibex parses
or statically type-checks them.

## Decision

With source-line conversion enabled, the generator constructs the complete
private reduction method as a Ruby source string and evaluates that method
definition once while the generated class is loaded:

```ruby
class_eval(method_source, grammar_file, action_line)
```

The method declaration, stack-context setup, named-reference bindings, and
result initialization occupy the same first logical source line before the
opaque action text. Consequently, the first character of the action retains
`action_line`, including when the action begins with a newline. Result-mode
epilogues follow the opaque source.

The generated class no longer stores `ACTION_CODE_*` constants and does not
evaluate action bodies during reductions. With line conversion disabled, the
generator retains the existing direct, readable method emission.

## Consequences

- Mapped semantic actions are compiled once per generated class load instead
  of once per reduction.
- Backtraces and `__FILE__`/`__LINE__` observations continue to refer to the
  grammar source.
- Generated mapped methods are less directly readable because their complete
  definitions are encoded as strings; `-l` remains the inspection mode.
- Ruby syntax errors in an action are reported when the generated class loads,
  as they were when Ruby parsed direct generated action methods.
- The generated RBS signature still describes the private method boundary,
  but Ibex does not statically inspect or type-check the opaque action body.
