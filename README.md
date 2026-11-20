# RDFS inference by SPARQL CONSTRUCTs

An early prototype that builds a set of SPARQL `CONSTRUCT` queries
implementing some RDFS inference rules for a given set of ontologies. So far
only `rdfs:subClassOf` and `rdfs:subPropertyOf` are supported.

The pipeline is written as **asynchronous jq filters**, run by
[async-jq-shell](https://github.com/miguel76/async-jq-shell): a filter,
instead of returning its output directly, can return a description of the
actions to run next (e.g. shell commands) and of the filter that will process
their output. See its [specification](https://github.com/miguel76/async-jq-shell/blob/main/SPEC.md)
for the step format.

## Requirements

- a POSIX `sh` and [jq](https://jqlang.github.io/jq/) 1.7;
- [jqpm](https://github.com/miguel76/jqpm) 0.2+, to install the dependencies
  (`pipx install jqpm`);
- Apache Jena's `arq` on the `PATH`.

## Running

Install the dependencies (async-jq-shell, as pinned in
`jqpackage-lock.json`) into `jq_modules/`:

```bash
jqpm install
```

Then:

```bash
./main.sh
```

writes the rules to `output/rewrite-rules.json`. To run the pipeline
directly, printing the rules on stdout:

```bash
jqpm exec async-jq main          # or: jq_modules/.bin/async-jq -L jq_modules main
```

The output is a JSON array of `CONSTRUCT` queries.

## How it works

- `flow/main.jq` calls one subflow per rule, `subclass` and `subproperty`
  (found as `flow/subclass/subclass.jq` and
  `flow/subproperty/subproperty.jq`), passing them the reference to
  `flow/query-ontologies.jq` as an argument, plus a passthrough rule
  (`CONSTRUCT WHERE {?s ?p ?o}`).
- Each subflow runs `query-ontologies` with its `relation.rq` as input.
  `query-ontologies` returns the `arq` command that runs that query on the
  ontologies in `ontologies/` (a shell step).
- The query results are passed to the subflow's `rule.jq`, a synchronous
  filter that turns them into a `CONSTRUCT` query.
- The results of all the rules are collected into an array.

```
flow/
  main.jq                  # entry point
  query-ontologies.jq      # SPARQL query file -> arq command
  subclass/
    subclass.jq            # the rdfs:subClassOf rule
    relation.rq            # SELECT ?class ?subclass
    rule.jq                # results -> CONSTRUCT query
  subproperty/
    ...                    # the same for rdfs:subPropertyOf
ontologies/                # the input ontologies
```
