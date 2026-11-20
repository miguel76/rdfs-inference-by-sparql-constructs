# Synchronous filter: SPARQL SELECT results in, CONSTRUCT query out.
(
        "CONSTRUCT {?subj a ?super_class} WHERE {" +
            "?subj a ?class " +
            "VALUES (?super_class ?class) {\(
                [
                    .results.bindings[] |
                    "(<\(.class.value)> <\(.subclass.value)>)"
                ] | join(" ")
            )}" +
        "}"
    )
