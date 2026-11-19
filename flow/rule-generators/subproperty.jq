{
    result: (
    "CONSTRUCT {?subj ?super_property ?obj} WHERE {" +
        "?subj ?property ?obj " +
        "VALUES (?super_property ?property) {\(
            [
                .results.bindings[] |
                "(<\(.property.value)> <\(.subproperty.value)>)"
            ] | join(" ")
        )}" +
    "}"
    )
}
