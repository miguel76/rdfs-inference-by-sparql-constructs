# RDFS inference by SPARQL CONSTRUCTs

An early prototype that builds a set of SPARQL `CONSTRUCT` queries
implementing some RDFS inference rules for a given set of ontologies. So far
only `rdfs:subClassOf` and `rdfs:subPropertyOf` are supported.

The pipeline is written as **async-jq flows**, run by
[async-jq-shell](https://github.com/miguel76/async-jq-shell): JSON
descriptions of dataflow pipelines, whose building blocks run shell
commands, read and write files, evaluate jq filters and run other flows. See
its [specification](https://github.com/miguel76/async-jq-shell/blob/main/SPEC.md)
for the flow format.

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
jqpm exec async-jq flow/main.json    # or: jq_modules/.bin/async-jq -L jq_modules flow/main.json
```

The output is a JSON array of `CONSTRUCT` queries.

## How it works

- `flow/main.json` binds two named inputs, computed by small jq filters with
  the async-jq library (so that they hold absolute paths):
  - `ontologies`: the ontology files in `ontologies/`;
  - `query_ontologies`: a flow running `flow/query-ontologies.json`, which
    the rules use without depending on where it is.

  It then runs, in parallel (keeping the order of the results), one subflow
  per rule, `flow/subclass/subclass.json` and
  `flow/subproperty/subproperty.json`, plus a passthrough rule
  (`CONSTRUCT WHERE {?s ?p ?o}`).
- Each rule reads its SPARQL query (`relation.rq`) and runs
  `query_ontologies` on it, which writes the query to a temporary file and
  runs it on the ontologies with `arq` (whose command line is built by
  `flow/arq.jq`).
- The query results are passed to the rule's `rule.jq`, a jq filter that
  turns them into a `CONSTRUCT` query.
- The results of all the rules are collected into an array.

```
flow/
  main.json                # entry point
  query-ontologies.json    # SPARQL query text -> arq results
  arq.jq                   # query file -> flow running arq
  subclass/
    subclass.json          # the rdfs:subClassOf rule
    relation.rq            # SELECT ?class ?subclass
    rule.jq                # results -> CONSTRUCT query
  subproperty/
    ...                    # the same for rdfs:subPropertyOf
ontologies/                # the input ontologies
```
