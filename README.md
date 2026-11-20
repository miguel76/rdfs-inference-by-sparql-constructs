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
./main.sh
```

writes the rules to `output/rewrite-rules.json`. To run the pipeline
directly:

```bash
./engine/exec.sh main
```

This calls `flow/main.jq`, which queries the ontologies in `ontologies/` with
the queries in `queries/` and passes the results to the rule generators in
`flow/rule-generators/`. The output is a JSON array of `CONSTRUCT` queries.

`exec.sh <filter>` calls the given filter with `null` input. The filter
reference is resolved as in a `call` step: `main` is `$FLOW_PATH/main.jq`,
`./x/y` is `x/y.jq` in the current directory. On success it prints the final
result (as JSON) on stdout and exits with 0. On failure it prints
`Error: ...` on stderr and exits with 1. Debug messages go to stderr.

Configuration, through environment variables (relative to the current
directory):

| Variable | Default | Meaning |
|---|---|---|
| `FLOW_PATH` | `flow` | root of the application's filters |
| `DATA_PATH` | `.` | root of the application's data files |

## Filters

Filters are jq programs in `.jq` files. The engine runs two kinds of filters:

- **asynchronous filters** output a *step* (described below): what to do
  next. They are run by `call` and `next`.
- **synchronous filters** are ordinary jq filters: they directly output their
  result, or raise an error. They are run by `sync_call` and `sync_next`.

Both get as input the input of the step that runs them.

Filters run by the engine can use the engine library with
`include "engine";` (see [Engine library](#engine-library)).

## Steps

A step describes something to execute. Executing a step takes an input (a
JSON value) and produces either a result (a JSON value) or an error.

A step is either a string, an array or an object. A string `"cmd"` is a
shorthand for `{"shell": "cmd"}`. An array `[s1, s2, ...]` runs the steps in
sequence, all with the same input; its result is the array of their results.

An object step has at most one **main field**, saying what the step does:

| Main field | Result |
|---|---|
| `"result": X` | `X` |
| `"error": E` | fails with error `E` (any JSON value) |
| `"shell": "cmd"` | the output of shell command `cmd` (see [Data formats](#data-formats)) |
| `"fetch_file": "ref"` | the content of the data file `ref` (see [Data formats](#data-formats)) |
| `"call": "ref"` | runs the asynchronous filter `ref` on the input, then executes the step it returns (with `null` input); the result is that step's result |
| `"sync_call": "ref"` | the output of the synchronous filter `ref` run on the input |
| `"action": S` | the result of step `S`, executed with the same input |
| *(none)* | the input itself |

and optionally these fields:

| Field | Meaning |
|---|---|
| `"next": N` | then execute step `N` with the result as input; the result of `N` is the result of the whole step |
| `"sync_next": "ref"` | shorthand for `"next": {"sync_call": "ref"}` |
| `"on_error": H` | if the main part of the step fails with error `E`, execute step `H` with `E` as input; its result (or error) replaces the failed one |
| `"format": "auto" \| "json" \| "text"` | for `shell` and `fetch_file`: how to parse the output (default `auto`) |

In `next` and `on_error`, a string is a reference to an asynchronous filter
(i.e. `"next": "ref"` is `"next": {"call": "ref"}`), not a shell command.

Unknown fields, or more than one main field, make the step invalid.

### `call` and `next`

`{"call": "f", "next": N}` runs `f` and then `N`. Rather than waiting for the
step returned by `f` to complete and then running `N`, the engine **inserts
`N` into the step returned by `f`**, before executing it, as its `next`:

- if the returned step has no `next`, `N` becomes its `next`;
- otherwise `N` is inserted (in the same way) in its `next`, so it ends up in
  the first step without `next` of the `.next.next...` chain;
- an array is first wrapped as `{"action": [...]}`.

So the continuation is passed down from call to call. This is equivalent to
running the returned step and then `N`, because `on_error` only covers the
main part of a step, never its `next`: a handler in the called filter never
catches errors raised by the caller's continuation. (For the same reason, when
the `call` step itself has an `on_error`, `N` is not inserted but simply run
afterwards.)

### Example

`flow/main.jq` returns (simplified):

```json
{
  "action": [
    {"action": "arq ... --query=/.../queries/subclass.rq",    "sync_next": "./rule-generators/subclass"},
    {"action": "arq ... --query=/.../queries/subproperty.rq", "sync_next": "./rule-generators/subproperty"},
    {"result": "CONSTRUCT WHERE {?s ?p ?o}"}
  ]
}
```

The engine runs the first `arq` query, passes its JSON results to the
synchronous filter `flow/rule-generators/subclass.jq`, which outputs a
`CONSTRUCT` query; then does the same for the second query. The results are
collected into an array, which is the final result.

## References to files

`call`, `sync_call`, `next`, `sync_next`, `on_error` and `exec.sh` refer to
filters; `fetch_file` and `resolve_file` refer to data files. References are
resolved to absolute paths:

| Reference | Resolved against |
|---|---|
| `./path`, `../path` | the directory of the filter that returned the step (the current filter) |
| `/path` | nothing: already absolute |
| `path` | the application root: `$FLOW_PATH` for filters, `$DATA_PATH` for data files |
| `scheme://...` | a URL: kept as it is (not supported yet by `fetch_file`; invalid for filters) |

The `.jq` extension is added to filter references that don't have it.

The engine resolves all the references in a step as soon as it gets it, so
the step can be moved to another filter's context (e.g. a `next` inserted by
a `call`) without changing meaning.

The resolution is implemented in a single place (`_resolve` in
`engine/lib/engine.jq`), meant to be extended with more complete mechanisms
for modular development, e.g. `module:path` references to modules registered
in the configuration, or search paths.

## Data formats

The `shell` and `fetch_file` steps turn bytes into a JSON result according to
their `format`:

| Format | Result |
|---|---|
| `auto` (default) | parsed as JSON if it is a single JSON value; otherwise the text, as a string; the empty string if empty |
| `json` | parsed as JSON; fails with a `parse` error if not valid |
| `text` | the text, as a string |

Details:

- `shell`: the command's stdout, with trailing newlines removed (as in shell
  command substitution). The command does not receive the step's input, and
  its stdin and stderr are those of `exec.sh`. It runs in the directory where
  `exec.sh` was started: use `resolve_file` to pass it absolute paths. If it
  exits with a non-zero status, the step fails.
- `fetch_file`: the file's content, as it is (trailing newlines included in
  `text`).

Possible improvements:

- pass the step input to shell commands on stdin, with an input format
  (`json`, compact or not, `text` for strings, `none`), and also as an
  environment variable or argument;
- a `bytes` format (base64-encoded string) for binary data, in both
  directions;
- a `json_seq` (or `lines`) format, giving an array of the JSON values (or
  lines) in the output;
- keep trailing newlines in shell output in `text` format (output through a
  temporary file instead of a command substitution);
- choose the default format from the file extension (`.json` as `json`,
  others as `text`) or, for URLs, from the response's content type;
- capture the stderr of failing shell commands into the error, as is done for
  filters;
- remote files for `fetch_file` (with `curl`), and caching.

## Error handling

Errors are values. Every step produces either a result or an error, and
errors are caught where they happen:

| Cause | Error |
|---|---|
| an `error` step | its value |
| a shell command fails | `{"type": "shell", "command", "status"}` |
| a filter fails (missing file, jq compile or runtime error, ...) | `{"type": "filter", "filter", "status", "message"}` (`message`: jq's stderr) |
| a synchronous filter outputs zero or several values | `{"type": "sync_call", "filter", "message"}` |
| a file can't be fetched | `{"type": "fetch", "file", "message"}` |
| a file can't be parsed in the requested format | `{"type": "parse", "format", "message"}` |
| an invalid step | `{"type": "step", "message", "step"}` |

By default, errors propagate:

- if the main part of a step fails, its `next` is **not** executed and the
  whole step fails with that error;
- in an array, all steps are executed; if any of them failed, the whole array
  fails with the first error.

### `on_error`

```json
{"action": "arq ...", "on_error": "./handle-error", "next": "./process"}
```

If the main part of the step fails with error `E`, the handler (here the
filter `handle-error`, but it can be any step) is executed with `E` as input,
and its result replaces the failed one, so it is then passed to `next`. The
handler can for example:

- recover with a fallback value: `{result: []}`
- re-raise, possibly adding context: `{error: {while: "querying", cause: .}}`
- retry or try an alternative: `"arq ... --query=..."`

If the main part succeeds, the handler is not executed. If the handler itself
fails, its error propagates as usual. The handler doesn't cover `next`: to
also handle errors raised there, wrap the step:
`{"action": {"action": ..., "next": ...}, "on_error": ...}`.

## Engine library

Filters run by the engine can `include "engine";` to use:

| Function | Result |
|---|---|
| `resolve_file`, `resolve_file(ref)` | the absolute path of data file `ref` (or of the input reference) |
| `resolve_filter`, `resolve_filter(ref)` | the absolute path of filter `ref` |

References are resolved as described in [References to files](#references-to-files),
`./` being relative to the filter run by the engine. This is useful to pass
absolute paths to shell commands, e.g.

```jq
include "engine";
{action: "cat \("./data.csv" | resolve_file | @sh)", next: "./parse"}
```

The engine passes its context to the filters it runs as
`--argjson engine_context '{"base": ..., "config": ...}'`.

## Engine

- `engine/exec.sh <filter>`: entry point. Computes the configuration and
  executes `{"call": "<filter>"}`.
- `engine/to-shell.jq`: translates a step into a POSIX shell script. It first
  normalizes the step (desugaring, resolving references), then translates
  it. The script for any step reads the step input from the shell variable
  `$__in` and prints exactly one JSON *envelope* on stdout, `{"result": X}`
  or `{"error": E}`. When a filter returns a step, the engine translates it
  with `to-shell.jq` again, at execution time.
- `engine/lib/engine.jq`: the engine library, used by both `to-shell.jq` and
  the filters.

A step's main part is always completed before its `next` starts, since the
engine must know whether the main part failed before deciding whether to run
the `next`.
