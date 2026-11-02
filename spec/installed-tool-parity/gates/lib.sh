# Helpers shared by this cycle's gates, sourced inside a temp_root.sh sandbox.
# Real-uv gates pass SEED_UV (a real uv with uvx beside it) through the scrub.
a=$(uname -m)
o="$UVM_SANDBOX/o"; mkdir -p "$o"
trash="$UVM_SANDBOX/trash"; mkdir -p "$trash"
data="${XDG_DATA_HOME:?temp_root.sh sets XDG_DATA_HOME}/uvm"
rec="$data/tools"
fail() { echo "FAIL: $*" >&2; exit 1; }
# LABEL CMD...: run a command that must succeed, keeping its output under $o.
run() {
    _l="$1"; shift
    if ! "$@" > "$o/$_l.out" 2> "$o/$_l.err"; then
        echo "FAIL ($_l): $* exited non-zero" >&2; cat "$o/$_l.err" >&2; exit 1
    fi
}
# KEY: seed versions/<ver> and current under KEY from SEED_UV. The installer
# does not run in every sandbox, and the cluster drive provisions through it.
seed() {
    _r="$UVM_ROOT/$1"; _v=$("$SEED_UV" --version | awk '{ print $2 }')
    mkdir -p "$_r/versions/$_v" && cp "$SEED_UV" "$(dirname "$SEED_UV")/uvx" "$_r/versions/$_v/" &&
        ln -s "versions/$_v" "$_r/current" || fail "seeding uv under $1"
}
# TOOL [KEY]: the tool's sorted dist-info names.
frozen() {
    for _d in "$UVM_ROOT/${2:-$a}/tools/$1"/lib/*/site-packages/*.dist-info; do
        [ -d "$_d" ] || continue; _b=${_d##*/}; echo "${_b%.dist-info}"
    done | LC_ALL=C sort
}
# TOOL [KEY]: the constraints the tool's environment implies, sorted.
envpins() {
    for _d in "$UVM_ROOT/${2:-$a}/tools/$1"/lib/*/site-packages/*.dist-info; do
        [ -d "$_d" ] || continue; _b=${_d##*/}; _b=${_b%.dist-info}
        [ -f "$_d/direct_url.json" ] || echo "${_b%-*}==${_b##*-}"
    done | LC_ALL=C sort
}
datalist() { if [ -d "$data" ]; then find "$data" -type f -exec cksum {} + | LC_ALL=C sort; fi; }
