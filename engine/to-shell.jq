# Translates a step description into a (POSIX sh) shell script.
#
# A step is one of:
#   "cmd"                      shorthand for {shell: "cmd"}
#   {shell: "cmd"}             run a shell command
#   {result: X}                output X
#   {error: E}                 fail with error E
#   {action: A, next: "f"}     run A, feed its result to filter f, then
#                              recursively execute the step f returns
#   {action: A}                just run A
#   {next: "f"}                run filter f with null input (-n)
#   [s1, s2, ...]              run steps in sequence, collect their results
#                              into an array
#
# The script generated for any step prints exactly one JSON envelope on
# stdout: either {"result": X} or {"error": E}. Errors are caught where they
# happen (failing shell command, failing filter, invalid step) and turned into
# an {"error": ...} envelope, which is then propagated by default:
#   - {action: A, next: f}: if A fails, f is not run and A's error is the
#     error of the whole step;
#   - [s1, s2, ...]: all elements are run; if any failed, the first error is
#     the error of the whole step.

def quote: tostring | @sh;

# shell command printing a JSON value
def print_json: "printf '%s\\n' \(tojson | @sh)";

def to_shell:
    if type == "array" then
        "( __envs=$( \(map(to_shell) | join("; ")) ); " +
        "printf '%s\\n' \"$__envs\" | jq -sc '(map(select(has(\"error\")))[0]) // {result: map(.result)}' )"
    else
        if type == "string" then {shell: .} end |
        . as $step |
        if has("result") then
            {result} | print_json
        elif has("error") then
            {error} | print_json
        elif has("shell") then
            # the output is parsed as JSON if possible, otherwise kept as a string
            "( __out=$( \(.shell)\n ); __st=$?; " +
            "if [ \"$__st\" -eq 0 ]; then " +
                "printf '%s' \"$__out\" | jq -Rsc '. as $s | {result: (try fromjson catch $s)}'; " +
            "else " +
                "jq -nc --argjson status \"$__st\" --arg command \(.shell | quote) " +
                "'{error: {type: \"shell\", command: $command, status: $status}}'; " +
            "fi )"
        elif has("next") then
            ("\($config.flow_path)/\(.next).jq" | quote) as $filter |
            (
                "if __step=$( " +
                    if has("action") then
                        "printf '%s\\n' \"$__env\" | jq -c '.result' | jq -c -f \($filter)"
                    else
                        "jq -nc -f \($filter)"
                    end +
                " ); then " +
                    "if __script=$( printf '%s\\n' \"$__step\" | " +
                        "jq -rn -f \("\($config.engine_path)/to-shell.jq" | quote) --argjson config \($config | tojson | quote) ); then " +
                        "eval \"$__script\"; " +
                    "else " +
                        ({error: {type: "step", filter: .next, message: "invalid step"}} | print_json) + "; " +
                    "fi; " +
                "else " +
                    "jq -nc --argjson status \"$?\" --arg filter \(.next | quote) " +
                    "'{error: {type: \"filter\", filter: $filter, status: $status}}'; " +
                "fi"
            ) as $follow_up |
            if has("action") then
                "( __env=$( \(.action | to_shell) ); " +
                "if printf '%s\\n' \"$__env\" | jq -e 'has(\"error\")' >/dev/null; then " +
                    "printf '%s\\n' \"$__env\"; " +
                "else \($follow_up); fi )"
            else
                "( \($follow_up) )"
            end
        elif has("action") then
            .action | to_shell
        else
            {error: {type: "step", message: "invalid step", step: .}} | print_json
        end
    end;

# a filter emitting several steps is equivalent to one emitting their array
[inputs] | if length == 1 then .[0] else . end | to_shell
