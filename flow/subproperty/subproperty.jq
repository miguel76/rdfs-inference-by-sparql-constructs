include "engine";

{
    input: ("./relation.rq" | resolve_file),
    call: "query-ontologies",
    sync_next: "./rule"
}