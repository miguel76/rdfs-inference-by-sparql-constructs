# Translates a step description into a shell script.
#
# A step is one of:
#   "cmd"                      shorthand for {shell: "cmd"}
#   {shell: "cmd"}             run a shell command; its stdout is the output
#   {result: X}                output X (as JSON)
#   {error: msg}               print msg on stderr and fail
#   {action: A, next: "f"}     run A, feed its output to filter f, then
#                              recursively execute the step f returns
#   {action: A}                just run A
#   {next: "f"}                run filter f with null input (-n)
#   [s1, s2, ...]              run steps in sequence, collect their (JSON)
#                              outputs into an array
def to_shell:
    if type == "array" then
        "{ \(map("(\(to_shell))") | join("; ")); } | jq -s '.'"
    else
        if type == "string" then {shell: .} end |
        if has("result") then
            "printf '%s\\n' \(.result | tojson | @sh)"
        elif has("error") then
            "printf 'Error: %s\\n' \(.error | tostring | @sh) >&2; exit 1"
        elif has("shell") then
            .shell
        elif has("action") or has("next") then
            [
                if has("action") then (.action | to_shell) else empty end,
                if has("next") then
                    "jq\(if has("action") then "" else " -n" end) -f \("\($config.flow_path)/\(.next).jq" | @sh)",
                    "jq -r -f \("\($config.engine_path)/to-shell.jq" | @sh) --argjson config \($config | tojson | @sh)",
                    # the previous filter emits a shell script: execute it
                    "{ script=$(cat); eval \"$script\"; }"
                else
                    empty
                end
            ] | join(" | ")
        else
            "Invalid step: \(tojson)" | error
        end
    end;

to_shell
