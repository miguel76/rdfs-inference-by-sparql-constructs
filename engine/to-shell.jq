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
#
# Each stage's output is captured in a variable before the next stage starts,
# so that (with `set -e`, `pipefail` and `inherit_errexit`, see exec.sh) a
# failure stops the flow before any later stage runs.
def to_shell:
    if type == "array" then
        "{ __out=$(\(map("(\(to_shell))") | join("; "))); printf '%s\\n' \"$__out\" | jq -s '.'; }"
    else
        if type == "string" then {shell: .} end |
        . as $step |
        if has("result") then
            "printf '%s\\n' \(.result | tojson | @sh)"
        elif has("error") then
            "printf 'Error: %s\\n' \(.error | tostring | @sh) >&2; exit 1"
        elif has("shell") then
            .shell
        elif has("next") then
            "jq\(if has("action") then "" else " -n" end) -f \("\($config.flow_path)/\(.next).jq" | @sh) | " +
            "jq -r -f \("\($config.engine_path)/to-shell.jq" | @sh) --argjson config \($config | tojson | @sh)" |
            # the follow-up filter emits a shell script: generate it, then execute it
            if $step | has("action") then
                "{ __in=$(\($step.action | to_shell)); __script=$(printf '%s\\n' \"$__in\" | \(.)); eval \"$__script\"; }"
            else
                "{ __script=$(\(.)); eval \"$__script\"; }"
            end
        elif has("action") then
            .action | to_shell
        else
            "Invalid step: \(tojson)" | error
        end
    end;

to_shell
