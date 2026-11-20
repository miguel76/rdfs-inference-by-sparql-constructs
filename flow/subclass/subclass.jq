include "engine";

{
    input: ("./relation.rq" | resolve_file),
    call: $query_ontologies,
    sync_next: "./rule"
}