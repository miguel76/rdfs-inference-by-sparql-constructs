# Translates a step description into a (POSIX sh) shell script.
# See README.md for the step format.
#
# Arguments:
#   --argjson config  engine configuration, with absolute paths:
#                     {"engine_path", "flow_path", "data_path"}
#   --arg base        absolute directory of the filter that produced the step,
#                     against which "./..." references are resolved
#   --argjson next    (optional) step to insert as continuation (see `add_next`)
#
# The generated script for a step reads the step's input (as JSON text) from
# the shell variable $__in and prints exactly one JSON envelope on stdout:
# either {"result": X} or {"error": E}.

include "engine";

def quote: tostring | @sh;

# shell command printing a JSON value
def print_json: "printf '%s\\n' \(tojson | @sh)";

# ---------------------------------------------------------------------------
# Normalization: desugars a step and resolves all the references it contains
# to absolute paths.

def main_keys: ["result", "error", "shell", "fetch_file", "call", "sync_call", "action"];
def other_keys: ["next", "sync_next", "on_error", "format"];
def formats: ["auto", "json", "text"];

# a step used as `next` or `on_error`: a string is a reference to a filter
def continuation:
    if type == "string" then {call: .} else . end;

def normalize:
    if type == "string" then
        {shell: .}
    elif type == "array" then
        map(normalize)
    elif type == "object" then
        ([keys[] | select(. as $k | main_keys + other_keys | index($k) | not)]) as $unknown |
        ([keys[] | select(. as $k | main_keys | index($k))]) as $main |
        if ($unknown | length) > 0 then
            error("unknown field(s) \($unknown | join(", ")) in step \(tojson)")
        elif ($main | length) > 1 then
            error("a step can have only one of \(main_keys | join(", ")), found \($main | join(", ")) in step \(tojson)")
        elif has("format") and (has("shell") or has("fetch_file") | not) then
            error("format can only be used with shell or fetch_file, in step \(tojson)")
        elif has("format") and (.format as $f | formats | index($f) | not) then
            error("unknown format \(.format | tojson), expected one of \(formats | join(", "))")
        elif has("next") and has("sync_next") then
            error("a step can't have both next and sync_next, in step \(tojson)")
        elif has("shell") and (.shell | type) != "string" then
            error("shell must be a string, in step \(tojson)")
        else . end |
        if has("sync_next") then .next = {sync_call: .sync_next} | del(.sync_next) else . end |
        if has("next") then .next |= (continuation | normalize) else . end |
        if has("on_error") then .on_error |= (continuation | normalize) else . end |
        if has("call") then .call |= resolve_filter_ref($base; $config) else . end |
        if has("sync_call") then .sync_call |= resolve_filter_ref($base; $config) else . end |
        if has("fetch_file") then .fetch_file |= resolve_file_ref($base; $config) else . end |
        if has("action") then .action |= normalize else . end
    else
        error("invalid step: \(tojson)")
    end;

# Inserts step $n (already normalized) as continuation of a normalized step:
# as its `next` if it has none, otherwise (recursively) in its `next`.
def add_next($n):
    if type == "array" then {action: ., next: $n}
    elif has("next") then .next |= add_next($n)
    else . + {next: $n}
    end;

# ---------------------------------------------------------------------------
# Translation

# jq program turning raw text (read with -Rs) into an envelope
def parse_program($format):
    {
        auto: ". as $s | {result: (if $s == \"\" then \"\" else (try fromjson catch $s) end)}",
        json: "try {result: fromjson} catch {error: {type: \"parse\", format: \"json\", message: .}}",
        text: "{result: .}"
    }[$format // "auto"];

# jq search path for the filters run by the engine: the engine library first,
# then jq's default search path
def jq_search_path:
    ["\($config.engine_path)/lib", "~/.jq", "$ORIGIN/../lib/jq", "$ORIGIN/../lib"] |
    map("-L \(quote)") | join(" ");

# Runs $script; if the envelope it prints has key $key ("result" or "error"),
# runs $then with the value at $key as input, otherwise prints the envelope.
def on_envelope($script; $key; $then):
    "( __env=$( \($script) ); " +
    "if printf '%s\\n' \"$__env\" | jq -e 'has(\"\($key)\")' >/dev/null; then " +
        "__in=$( printf '%s\\n' \"$__env\" | jq -c '.\($key)' ); \($then); " +
    "else printf '%s\\n' \"$__env\"; fi )";

# Runs filter $path on $__in. Sets $__out (stdout), $__st (exit status) and
# $__msg (stderr). The filter gets the engine context (for resolve_file).
def run_filter($path):
    {base: ($path | _dirname), config: $config} as $context |
    "__errf=$(mktemp) || { \({error: {type: "engine", message: "mktemp failed"}} | print_json); exit; }; " +
    "__out=$( printf '%s\\n' \"$__in\" | jq -c \(jq_search_path) --argjson engine_context \($context | tojson | quote) -f \($path | quote) 2>\"$__errf\" ); " +
    "__st=$?; __msg=$(cat \"$__errf\"); rm -f \"$__errf\"; ";

def filter_error($path):
    "jq -nc --argjson status \"$__st\" --arg message \"$__msg\" --arg filter \($path | quote) " +
    "'{error: {type: \"filter\", filter: $filter, status: $status, message: $message}}'";

# stderr of a successful filter (e.g. debug messages) is passed through
def pass_messages: "if [ -n \"$__msg\" ]; then printf '%s\\n' \"$__msg\" >&2; fi; ";

# {call: $path}, with optional continuation $next inserted in the returned step
def call_script($path; $next):
    "( \(run_filter($path))" +
    "if [ \"$__st\" -eq 0 ]; then \(pass_messages)" +
        "if __script=$( printf '%s\\n' \"$__out\" | " +
            "jq -rn -L \("\($config.engine_path)/lib" | quote) -f \("\($config.engine_path)/to-shell.jq" | quote) " +
            "--argjson config \($config | tojson | quote) --arg base \($path | _dirname | quote)" +
            (if $next then " --argjson next \($next | tojson | quote)" else "" end) +
        " ); then __in=null; eval \"$__script\"; " +
        "else \({error: {type: "engine", filter: $path, message: "translation of the returned step failed"}} | print_json); fi; " +
    "else \(filter_error($path)); fi )";

def sync_call_script($path):
    "( \(run_filter($path))" +
    "if [ \"$__st\" -eq 0 ]; then \(pass_messages)" +
        "printf '%s\\n' \"$__out\" | jq -sc --arg filter \($path | quote) " +
        "'if length == 1 then {result: .[0]} " +
        "else {error: {type: \"sync_call\", filter: $filter, message: \"expected exactly one output, got \\(length)\"}} end'; " +
    "else \(filter_error($path)); fi )";

def shell_script($command; $format):
    "( __out=$( \($command)\n ); __st=$?; " +
    "if [ \"$__st\" -eq 0 ]; then " +
        "printf '%s' \"$__out\" | jq -Rsc \(parse_program($format) | quote); " +
    "else " +
        "jq -nc --argjson status \"$__st\" --arg command \($command | quote) " +
        "'{error: {type: \"shell\", command: $command, status: $status}}'; " +
    "fi )";

def fetch_file_script($path; $format):
    if $path | _is_url then
        {error: {type: "fetch", file: $path, message: "remote files are not supported yet"}} | print_json
    else
        "( if [ -f \($path | quote) ] && [ -r \($path | quote) ]; then " +
            "jq -Rsc \(parse_program($format) | quote) < \($path | quote) || " +
            ({error: {type: "fetch", file: $path, message: "cannot read file"}} | print_json) + "; " +
        "else \({error: {type: "fetch", file: $path, message: "file not found"}} | print_json); fi )"
    end;

# translates a normalized step
def translate:
    if type == "array" then
        "( __envs=$( \(map(translate) | join("; ")) ); " +
        "printf '%s\\n' \"$__envs\" | jq -sc '(map(select(has(\"error\")))[0]) // {result: map(.result)}' )"
    elif has("call") and has("next") and (has("on_error") | not) then
        # the continuation is inserted in the step returned by the filter
        call_script(.call; .next)
    else
        . as $step |
        if has("result") then {result} | print_json
        elif has("error") then {error} | print_json
        elif has("shell") then shell_script(.shell; .format)
        elif has("fetch_file") then fetch_file_script(.fetch_file; .format)
        elif has("call") then call_script(.call; null)
        elif has("sync_call") then sync_call_script(.sync_call)
        elif has("action") then .action | translate
        else "( printf '%s\\n' \"$__in\" | jq -c '{result: .}' )"  # no main part: the input is the result
        end |
        if $step | has("on_error") then on_envelope(.; "error"; $step.on_error | translate) else . end |
        if $step | has("next") then on_envelope(.; "result"; $step.next | translate) else . end
    end;

# a filter emitting several steps is equivalent to one emitting their array
[inputs] | (if length == 1 then .[0] else . end) as $step |
try (
    $step | normalize |
    if $ARGS.named.next then add_next($ARGS.named.next) else . end |
    translate
) catch (
    {error: {type: "step", message: ., step: $step}} | print_json
)
