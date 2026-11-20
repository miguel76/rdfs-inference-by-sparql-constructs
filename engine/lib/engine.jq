# Engine library, available to every filter run by the engine:
#
#   include "engine";
#
# Public API:
#   resolve_file, resolve_file($ref)      absolute path of a data file
#   resolve_filter, resolve_filter($ref)  absolute path of a filter
#
# References are resolved as described in `_resolve` below. Relative
# references ("./x", "../x") are relative to the directory of the filter
# currently executed by the engine (not of the module calling the function).

# ---------------------------------------------------------------------------
# Paths

# Removes "", "." and ".." segments from a path.
def _normalize_path:
    startswith("/") as $absolute |
    reduce (split("/")[] | select(. != "" and . != ".")) as $segment ([];
        if $segment != ".." then . + [$segment]
        elif length > 0 and .[-1] != ".." then .[:-1]
        elif $absolute then .
        else . + [".."]
        end
    ) |
    (if $absolute then "/" else "" end) + join("/");

def _dirname:
    if test("/") then sub("/[^/]*$"; "") | if . == "" then "/" else . end
    else "."
    end;

def _is_url: test("^[A-Za-z][A-Za-z0-9+.-]*://");

# ---------------------------------------------------------------------------
# Resolution of references
#
# Resolves the reference in input to an absolute path (or URL):
#   "scheme://..."        a URL, kept as it is
#   "/abs/path"           an absolute path
#   "./path", "../path"   relative to $base, the directory of the current filter
#   "path"                relative to $root, the root directory configured for
#                         this kind of file (flow_path for filters, data_path
#                         for data files)
#
# Extension point: further kinds of references can be added here as new
# branches, e.g. "<module>:<path>" for modules registered in the configuration
# (mapping module names to directories or URLs), or a search path (as jq's
# -L) tried in order. Being resolved to absolute paths early, the references
# in a step can then be moved freely between filters (see `next` insertion in
# to-shell.jq).
def _resolve($base; $root):
    if type != "string" then error("invalid file reference: \(tojson)")
    elif _is_url then .
    elif startswith("/") then _normalize_path
    elif . == "." or . == ".." or startswith("./") or startswith("../") then
        "\($base)/\(.)" | _normalize_path
    else
        "\($root)/\(.)" | _normalize_path
    end;

# $config: engine configuration ({flow_path, data_path, ...})
def resolve_filter_ref($base; $config):
    if _is_url then error("remote filters are not supported: \(.)") else . end |
    _resolve($base; $config.flow_path) |
    if endswith(".jq") then . else . + ".jq" end;

def resolve_file_ref($base; $config):
    _resolve($base; $config.data_path);

# ---------------------------------------------------------------------------
# API for filters run by the engine, which passes them its context as
# --argjson engine_context '{"base": <dir of the filter>, "config": {...}}'

def _engine_context:
    $ARGS.named.engine_context //
    error("no engine context: the filter must be run by the engine");

def resolve_file: _engine_context as $c | resolve_file_ref($c.base; $c.config);
def resolve_file($ref): $ref | resolve_file;

def resolve_filter: _engine_context as $c | resolve_filter_ref($c.base; $c.config);
def resolve_filter($ref): $ref | resolve_filter;
