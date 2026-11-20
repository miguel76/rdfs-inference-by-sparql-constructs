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

This calls `flow/main.jq`, which calls one subflow per rule
(`flow/subclass/`, `flow/subproperty/`). Each subflow queries the ontologies
in `ontologies/` with its `relation.rq` (through `flow/query-ontologies.jq`)
and turns the results into a `CONSTRUCT` query with its `rule.jq`. The output
is a JSON array of `CONSTRUCT` queries.

`exec.sh [options] <filter>` calls the given filter. The filter reference is
resolved as in a `call` step: `main` is `$FLOW_PATH/main.jq` (or
`$FLOW_PATH/main/main.jq`), `./x/y` is `x/y.jq` (or `x/y/y.jq`) in the current
directory. On success it prints the final result (as
JSON) on stdout and exits with 0. On failure it prints `Error: ...` on stderr
and exits with 1. Debug messages go to stderr.

| Option | Meaning |
|---|---|
| `--input JSON` | the input of the filter (default: `null`) |
| `--stdin` | read the input of the filter (exactly one JSON value) from stdin |
| `--args JSON` | named arguments for the filter (an object, as [`args`](#call-and-sync_call-arguments) in a `call` step) |

For example:

```bash
echo '{"x": 1}' | ./engine/exec.sh --stdin --args '{"verbose": true}' ./my-flow
```

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
| `"call": "ref"` | runs the asynchronous filter `ref` on the input, then executes the step it returns (with `null` input, see [Inputs](#inputs)); the result is that step's result |
| `"sync_call": "ref"` | the output of the synchronous filter `ref` run on the input |
| `"action": S` | the result of step `S`, executed with the same input |
| *(none)* | the input itself |

and optionally these fields:

| Field | Meaning |
|---|---|
| `"input": X` | the step's input is `X`, instead of the one it would get (see [Inputs](#inputs)) |
| `"args": {...}` | for `call` and `sync_call`: named arguments for the filter (see [Arguments](#call-and-sync_call-arguments)) |
| `"next": N` | then execute step `N` with the result as input; the result of `N` is the result of the whole step |
| `"sync_next": "ref"` | shorthand for `"next": {"sync_call": "ref"}` |
| `"on_error": H` | if the main part of the step fails with error `E`, execute step `H` with `E` as input; its result (or error) replaces the failed one |
| `"format": "auto" \| "json" \| "text"` | for `shell` and `fetch_file`: how to parse the output (default `auto`) |

In `next` and `on_error`, a string is a reference to an asynchronous filter
(i.e. `"next": "ref"` is `"next": {"call": "ref"}`), not a shell command.

Unknown fields, or more than one main field, make the step invalid.

### Inputs

The input of a step comes from where the step is:

| Step | Input |
|---|---|
| the step run by `exec.sh` | `null`, or as given by `--input` / `--stdin` |
| a step returned by a filter | `null` |
| `action`, array elements | the input of the enclosing step |
| `next` | the result of the main part of the enclosing step |
| `on_error` | the error |

A step returned by a filter is thus self-contained: any data it needs is in
the step itself. To give a step a specific input, use the `input` field:

```jq
{call: "./g", input: .records, next: "./h"}
```

`{"input": X, ...rest}` is a shorthand for `{"result": X, "next": {...rest}}`:
the step's own `next` and `on_error` apply to `rest`, as usual. `input`
can't be used with `result` or `error`.

Note that `input` replaces the input the step would otherwise get: in
`{"action": A, "next": {"call": "g", "input": X}}` the result of `A` is
discarded.

### `call` and `sync_call` arguments

Besides their input (the data flowing through the pipeline), filters can be
given named arguments, meant for parameters (configuration, options, names,
...), with `args`:

```jq
{call: "./generate-rule", args: {rule: "subclass"}, input: .bindings}
```

Each entry is passed to the filter as `--argjson name value`: the filter can
use it as `$rule`, or through `$ARGS.named`. Names must be valid jq variable
names; `engine_context`, `ENV`, `ARGS` and names starting with `__` are
reserved. A filter using a variable that it is not given fails to compile.

Arguments are passed on the command line, so they are subject to the
operating system's limit on the size of a command-line argument (128 KB on
Linux): pass large data as `input`, which has no such limit.

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
[
  {"call": "subclass",    "args": {"query_ontologies": "/.../flow/query-ontologies"}},
  {"call": "subproperty", "args": {"query_ontologies": "/.../flow/query-ontologies"}},
  {"result": "CONSTRUCT WHERE {?s ?p ?o}"}
]
```

The engine calls `flow/subclass/subclass.jq` (see
[Filter lookup](#filter-lookup)), which returns:

```json
{"input": "/.../flow/subclass/relation.rq", "call": "/.../flow/query-ontologies", "sync_next": "./rule"}
```

`query-ontologies.jq` gets the path of the query as input and returns the
`arq` command to run (a string, i.e. a shell step); its JSON results are
passed to the synchronous filter `flow/subclass/rule.jq`, which outputs a
`CONSTRUCT` query. The same happens for `subproperty`, and the results are
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

The engine resolves all the references in a step as soon as it gets it, so
the step can be moved to another filter's context (e.g. a `next` inserted by
a `call`) without changing meaning.

The resolution is implemented in a single place (`_resolve` in
`engine/lib/engine.jq`), meant to be extended with more complete mechanisms
for modular development, e.g. `module:path` references to modules registered
in the configuration, or search paths.

### Filter lookup

Filter references follow jq's convention for modules: `foo/bar` is the file
`foo/bar.jq` or, if it doesn't exist, `foo/bar/bar.jq`. So a filter can live
in a directory with the same name, together with the files it uses:

```
flow/subclass/subclass.jq    # {"call": "subclass"}
flow/subclass/relation.rq    # "./relation.rq" from subclass.jq
flow/subclass/rule.jq        # "./rule" from subclass.jq
```

A reference ending in `.jq` is that file only. `./` references in a filter
(and in the steps it returns) are relative to the directory of the file
actually found.

jq can't check whether a file exists, so the lookup is done in two stages:
references are resolved to absolute references without the extension (as
above), and the engine picks the file when it runs the filter. If no candidate
exists, the step fails with
`{"type": "filter", "filter", "message": "filter not found", "candidates"}`.

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
| a filter is not found | `{"type": "filter", "filter", "message", "candidates"}` (`candidates`: the files tried) |
| a filter fails (jq compile or runtime error, ...) | `{"type": "filter", "filter", "status", "message"}` (`message`: jq's stderr) |
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
| `resolve_filter`, `resolve_filter(ref)` | the absolute reference to filter `ref`, usable in steps (without `.jq`: the file is chosen at execution time, see [Filter lookup](#filter-lookup)) |
| `filter_candidates`, `filter_candidates(ref)` | the files that may hold filter `ref`, in lookup order |

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

- `engine/exec.sh [options] <filter>`: entry point. Computes the
  configuration and executes `{"call": "<filter>", "input": ..., "args": ...}`.
- `engine/to-shell.jq`: translates a step into a POSIX shell script. It first
  normalizes the step (desugaring, resolving references), then translates
  it. The script for any step reads the step input from the shell variable
  `$__in` and prints exactly one JSON *envelope* on stdout, `{"result": X}`
  or `{"error": E}`. When a filter returns a step, the engine translates it
  with `to-shell.jq` again, at execution time.
- `engine/lib/engine.jq`: the engine library, used by both `to-shell.jq` and
  the filters.

Data that can be large (steps, inputs, results, error messages) is always
passed to `jq` on stdin or embedded in the generated script, never as a
command-line argument, so it is not subject to the operating system's limit
on argument size. The only exception is `args`.

A step's main part is always completed before its `next` starts, since the
engine must know whether the main part failed before deciding whether to run
the `next`.
