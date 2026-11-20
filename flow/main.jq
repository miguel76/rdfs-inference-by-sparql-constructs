["subclass", "subproperty"] as $rules |

$rules |
map({
    call: "\(.)/\(.)"
}) + [
    {result: "CONSTRUCT WHERE {?s ?p ?o}"}
]
