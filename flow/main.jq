include "async-jq";

["subclass", "subproperty"] as $rules |

$rules |
map({
    call: .,
    args: {
        query_ontologies: ("./query-ontologies" | resolve_filter)
    }
}) + [
    {result: "CONSTRUCT WHERE {?s ?p ?o}"}
]
