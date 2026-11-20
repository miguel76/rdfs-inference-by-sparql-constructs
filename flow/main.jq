include "engine";

["ccso.owl", "data.owl", "top-level.owl"] as $ontologies |
["subclass", "subproperty"] as $rules |

"arq --results=JSON \(
    $ontologies | map("--data=\("ontologies/\(.)" | resolve_file | @sh)") | join(" ")
)" as $arq_prefix |

{
    action: (
        $rules |
        map({
            action: "\($arq_prefix) --query=\("queries/\(.).rq" | resolve_file | @sh)",
            sync_next: "./rule-generators/\(.)"
        }) + [
            {result: "CONSTRUCT WHERE {?s ?p ?o}"}
        ]
    )
}
