# Input: the path of a file holding a SPARQL query. Named input: ontologies,
# the absolute paths of the ontology files. Output: a flow running the query
# on the ontologies with arq, with JSON results.
import "async-jq" as aj;

aj::shell("arq --results=JSON \(
    $ontologies | map("--data=\(@sh)") | join(" ")
) --query=\(@sh)")
