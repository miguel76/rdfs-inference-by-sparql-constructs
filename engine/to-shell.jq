def to_shell:
#    debug("to_shell input: \(.)") |
#    debug($config) |
    if type=="array" then 
        "{ \(
            map("(\(to_shell))") |
            join("; ")
        ); }"
    else
        if type=="string" then
            {shell: .}
        end |
        if .result then
            "echo '\(.result)'"
        elif .error then
            "echo 'Error: \(.error)'; exit 1"
        elif .shell then
            .shell
        elif .action or .next then
            [
                if .action then
                    ( 
                        (.action | to_shell),
                        if .action | type == "array" then
                            "jq -s '.'"
                        else
                            empty
                        end
                    )
                else
                    empty
                end
            ] as $actions |
            "$(\(
                [
                    $actions[],
                    if .next then
                        (
                            "jq -f '\($config.flow_path)/\(.next).jq'\(
                                if .action | not then " -n" else "" end
                            )",
                            "jq -r -f '\($config.engine_path)/to-shell.jq' --argjson config '\($config | tojson)'"
                        )
                    else
                        empty
                    end
                ] | join(" | ")
            ))"
        end
    end;
    # debug("to_shell output: \(.)");


to_shell
