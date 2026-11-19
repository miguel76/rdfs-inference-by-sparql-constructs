# RDFS inference by SPARQL CONSTRUCTs

An early prototype that builds a set of SPARQL `CONSTRUCT` queries
implementing some RDFS inference rules for a given set of ontologies. So far
only `rdfs:subClassOf` and `rdfs:subPropertyOf` are supported.

The project is also an experiment in running **asynchronous jq filters**: a
filter, instead of returning its output directly, can return a description of
the actions to run next (e.g. shell commands) and of the filter that will
process their output. A small generic engine (`engine/`) executes these
descriptions.

## Running

Requirements: a POSIX `sh`, [jq](https://jqlang.github.io/jq/) (1.7) and,
for this pipeline, Apache Jena's `arq` on the `PATH`.

```bash
./engine/exec.sh main
```

This runs the flow `flow/main.jq`, which queries the ontologies in
`ontologies/` with the queries in `queries/` and passes the results to the
rule generators in `flow/rule-generators/`. The output is a JSON array with
one `CONSTRUCT` query per rule. Progress and debug messages go to stderr.

On success `exec.sh` prints the final result (as JSON) on stdout and exits
with 0. On failure it prints `Error: ...` on stderr and exits with 1.

## Flows

A *flow* is a jq filter stored in `flow/<name>.jq` and referred to by
`<name>` (without the `.jq` extension, possibly with subdirectories, e.g.
`rule-generators/subclass`). Each flow outputs a *step*, which the engine then
executes.

## Step format

| Step | Meaning |
|---|---|
| `{"result": X}` | Done: the output is `X`. |
| `{"error": E}` | Fail with error `E` (any JSON value). |
| `{"shell": "cmd"}` | Run a shell command. The output is its stdout. |
| `"cmd"` | Shorthand for `{"shell": "cmd"}`. |
| `{"action": A, "next": "f"}` | Run step `A`, give its output as input to flow `f`, then execute the step `f` returns. |
| `{"next": "f"}` | Run flow `f` with `null` input (`jq -n`), then execute the step it returns. |
| `{"action": A}` | Run step `A`; the output is its output. |
| `[s1, s2, ...]` | Run the steps in sequence; the output is the array of their outputs. |

Steps nest freely: an `action` can be any step, including an array or another
`{action, next}`. A flow that outputs several steps is treated as if it had
output the array of them.

### Output of a shell command

If the command succeeds (exit status 0), its stdout becomes the step's output:

- parsed as JSON, if it is a single JSON value (e.g. `arq --results=JSON`);
- otherwise the raw text, as a JSON string (e.g. `echo hello` gives
  `"hello"`);
- no output at all gives the empty string `""`.

Trailing newlines are removed, as in shell command substitution. The command's
stderr is not captured: it goes straight to the terminal.

If the command fails, the step fails with the error
`{"type": "shell", "command": "...", "status": N}`.

### Example

`flow/main.jq` returns (simplified):

```json
{
  "action": [
    {"action": "arq ... --query=queries/subclass.rq",    "next": "rule-generators/subclass"},
    {"action": "arq ... --query=queries/subproperty.rq", "next": "rule-generators/subproperty"}
  ]
}
```

The engine runs the first `arq` query, passes its JSON results to
`flow/rule-generators/subclass.jq`, which returns `{"result": "CONSTRUCT ..."}`;
then does the same for the second query. The two results are collected into
an array, which is the final output.

## Error handling

Errors are values. Every step produces either a result or an error, and
errors are caught where they happen:

| Cause | Error |
|---|---|
| a flow returns `{"error": E}` | `E` |
| a shell command fails | `{"type": "shell", "command": "...", "status": N}` |
| a flow fails (missing file, jq compile or runtime error, ...) | `{"type": "filter", "filter": "f", "status": N}` |
| a flow returns something that is not a valid step | `{"type": "step", ...}` |

By default, errors propagate:

- in `{"action": A, "next": "f"}`, if `A` fails, `f` is **not** run and the
  whole step fails with `A`'s error;
- in `[s1, s2, ...]`, all steps are run; if any of them failed, the whole step
  fails with the first error.

### `on_error`

Any object step can have an `on_error` field naming a flow:

```json
{"action": "arq ...", "next": "process", "on_error": "handle-error"}
```

If the step fails with error `E` (whatever the cause: the action, the `next`
flow, or anything the step returned by `next` runs), the flow
`handle-error` is run with `E` as input, and the step it returns is executed
in place of the failed one. The handler can for example:

- recover with a fallback value: `{result: []}`
- re-raise, possibly adding context: `{error: {while: "querying", cause: .}}`
- retry or try an alternative: `"arq ... --query=queries/fallback.rq"`

If the step succeeds, the handler is not run. If the handler itself fails,
its error propagates as usual.

To attach a handler to an array of steps, wrap it in an `action`:
`{"action": [s1, s2], "on_error": "g"}`.

## Engine

- `engine/exec.sh <flow>`: entry point. Executes `{"next": "<flow>"}` and
  prints the final result (or error).
- `engine/to-shell.jq`: translates a step into a POSIX shell script. The
  script for any step prints exactly one JSON *envelope* on stdout,
  `{"result": X}` or `{"error": E}`. When a step has a follow-up flow, the
  engine runs the flow and translates the step it returns with
  `to-shell.jq` again, at execution time.

A step's action is always completed before its follow-up flow starts, since
the engine must know whether the action failed before deciding whether to
run the follow-up.
