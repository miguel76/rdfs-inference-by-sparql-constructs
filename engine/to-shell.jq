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
# Any object step may also have an `on_error: "g"` field: if the step fails
# with error E, filter g is run with E as input and the step it returns is
# executed in place of the failed one (it may recover with {result: ...},
# re-raise with {error: ...}, retry, ...).
#
# The script generated for any step prints exactly one JSON envelope on
# stdout: either {"result": X} or {"error": E}. Errors are caught where they
# happen (failing shell command, failing filter, invalid step) and turned into
# an {"error": ...} envelope, which is then propagated by default:
#   - {action: A, next: f}: if A fails, f is not run and A's error is the
#     error of the whole step;
#   - [s1, s2, ...]: all elements are run; if any failed, the first error is
#     the error of the whole step;
#   - unless the step has an on_error handler.

def quote: tostring | @sh;

# shell command printing a JSON value
def print_json: "printf '%s\\n' \(tojson | @sh)";

# Shell script running filter $name, then executing the step it returns.
# The filter's input is the $field ("result" or "error") of the envelope in
# shell variable $__env, or null if $field is null.
def follow_up($name; $field):
    ("\($config.flow_path)/\($name).jq" | quote) as $filter |
    "if __step=$( " +
        if $field then
            "printf '%s\\n' \"$__env\" | jq -c '.\($field)' | jq -c -f \($filter)"
        else
            "jq -nc -f \($filter)"
        end +
    " ); then " +
        "if __script=$( printf '%s\\n' \"$__step\" | " +
            "jq -rn -f \("\($config.engine_path)/to-shell.jq" | quote) --argjson config \($config | tojson | quote) ); then " +
            "eval \"$__script\"; " +
        "else " +
            ({error: {type: "step", filter: $name, message: "invalid step"}} | print_json) + "; " +
        "fi; " +
    "else " +
        "jq -nc --argjson status \"$?\" --arg filter \($name | quote) " +
        "'{error: {type: \"filter\", filter: $filter, status: $status}}'; " +
    "fi";

# Shell script running script $script; if its envelope has key $key ("result"
# or "error"), $then is run (with the envelope in $__env), otherwise the
# envelope is printed as it is.
def on_envelope($script; $key; $then):
    "( __env=$( \($script) ); " +
    "if printf '%s\\n' \"$__env\" | jq -e 'has(\"\($key)\")' >/dev/null; then " +
        "\($then); " +
    "else printf '%s\\n' \"$__env\"; fi )";

def to_shell:
    if type == "array" then
        "( __envs=$( \(map(to_shell) | join("; ")) ); " +
        "printf '%s\\n' \"$__envs\" | jq -sc '(map(select(has(\"error\")))[0]) // {result: map(.result)}' )"
    elif type == "object" and has("on_error") then
        on_envelope(del(.on_error) | to_shell; "error"; follow_up(.on_error; "error"))
    else
        if type == "string" then {shell: .} end |
        if has("result") then
            {result} | print_json
        elif has("error") then
            {error} | print_json
        elif has("shell") then
            # the output is parsed as JSON if possible, otherwise kept as a
            # string (no output at all gives the empty string)
            "( __out=$( \(.shell)\n ); __st=$?; " +
            "if [ \"$__st\" -eq 0 ]; then " +
                "printf '%s' \"$__out\" | jq -Rsc '. as $s | {result: (if $s == \"\" then \"\" else (try fromjson catch $s) end)}'; " +
            "else " +
                "jq -nc --argjson status \"$__st\" --arg command \(.shell | quote) " +
                "'{error: {type: \"shell\", command: $command, status: $status}}'; " +
            "fi )"
        elif has("next") then
            if has("action") then
                on_envelope(.action | to_shell; "result"; follow_up(.next; "result"))
            else
                "( \(follow_up(.next; null)) )"
            end
        elif has("action") then
            .action | to_shell
        else
            {error: {type: "step", message: "invalid step", step: .}} | print_json
        end
    end;

# a filter emitting several steps is equivalent to one emitting their array
[inputs] | if length == 1 then .[0] else . end | to_shell
