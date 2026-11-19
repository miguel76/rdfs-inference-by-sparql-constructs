["ccso.owl", "data.owl", "top-level.owl"] as $ontologies |
["subclass", "subproperty"] as $rules |

"arq --results=JSON \(
    $ontologies | map("--data=ontologies/\(.)") | join(" ")
)" as $arq_prefix | 

debug("main.jq") |

{
    action:
        $rules |
        map({
            action: "\($arq_prefix) --query=queries/\(.).rq",
            next: "rule-generators/\(.)"
        })
}

