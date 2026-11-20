include "engine";

["ccso.owl", "data.owl", "top-level.owl"] as $ontologies |

"arq --results=JSON \(
    $ontologies | map("--data=\("ontologies/\(.)" | resolve_file | @sh)") | join(" ")
) --query=\(. | @sh)"
