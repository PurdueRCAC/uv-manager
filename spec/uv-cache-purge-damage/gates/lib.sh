# Helpers shared by this cycle's gates, sourced inside a temp_root.sh sandbox.
# Real-uv gates pass SEED_UV (a real uv with uvx beside it) through the scrub.
a=$(uname -m)
root="$UVM_ROOT/$a"; c="$root/cache"
o="$UVM_SANDBOX/o"; mkdir -p "$o"
trash="$UVM_SANDBOX/trash"; mkdir -p "$trash"
w="$UVM_SANDBOX/w"; mkdir -p "$w"
golden="$UVM_SANDBOX/golden"
UV_PYTHON_PREFERENCE=only-managed; export UV_PYTHON_PREFERENCE
fail() { echo "FAIL: $*" >&2; exit 1; }
# LABEL CMD...: run a command that must succeed, keeping its output under $o.
run() {
    _l="$1"; shift
    if ! "$@" > "$o/$_l.out" 2> "$o/$_l.err"; then
        echo "FAIL ($_l): $* exited non-zero" >&2; cat "$o/$_l.err" >&2; exit 1
    fi
}
# Seed versions/<ver> and current from SEED_UV: the installer does not run in
# every sandbox, and the cluster drive provisions through it. A harness step.
seed() {
    _v=$("$SEED_UV" --version | awk '{ print $2 }')
    mkdir -p "$root/versions/$_v" && cp "$SEED_UV" "$(dirname "$SEED_UV")/uvx" "$root/versions/$_v/" &&
        ln -s "versions/$_v" "$root/current" || fail "seeding uv"
}
# NAME DEPS BODY: a PEP 723 script under $w.
script() {
    printf '# /// script\n# requires-python = ">=3.12"\n# dependencies = [%s]\n# ///\n%s\n' "$2" "$3" > "$w/$1"
}
# The subjects: two script environments, three cached uvx environments (one
# with a binary executable), and the wheels they were built from.
subjects() {
    run py uv python install 3.12
    script s.py '"tqdm==4.67.1"' 'import tqdm, tqdm.std; print("s ok", tqdm.__version__)'
    script r.py '"rich==13.9.4"' 'import rich.console, pygments.lexers, markdown_it; print("r ok", pygments.__version__)'
    script n.py '"tqdm==4.67.1"' 'import tqdm, tqdm.std; print("n ok", tqdm.__version__)'
    run b1 uv run --no-project "$w/s.py"; run b2 uv run --no-project "$w/r.py"
    run b3 uvx tqdm==4.67.1 --version; run b4 uvx flake8==7.1.1 --version; run b5 uvx ruff==0.8.4 --version
    cp -pPR "$c" "$golden" || fail "keeping the healthy cache"
}
restore() { find "$c" -delete && cp -pPR "$golden" "$c" || fail "restoring the healthy cache"; }
# PKG: the script environment, or the link of the cached environment, that
# holds PKG; WHEEL NAME: the unpacked wheel's link.
senv() { for _d in "$c"/environments-v2/*-*/; do [ -d "${_d}lib/python3.12/site-packages/$1" ] && { echo "${_d%/}"; return; }; done; }
xlink() { for _l in "$c"/environments-v2/*/*; do [ -L "$_l" ] && [ -d "$_l/lib/python3.12/site-packages/$1" ] && { echo "$_l"; return; }; done; }
wlink() { for _l in "$c"/wheels-v*/pypi/"$1"/*; do [ -L "$_l" ] && { echo "$_l"; return; }; done; }
real() { (cd "$1" && pwd -P); }
# DIR: every file under DIR, links included, sorted; with STEP, every STEP-th.
files() { find "$1" \( -type f -o -type l \) | LC_ALL=C sort; }
nth() { awk -v n="$1" 'NR % n == 0'; }
# Remove each path on stdin: files and links only, the shape a purge leaves.
purge() { while IFS= read -r _p; do [ -n "$_p" ] && { unlink "$_p" || fail "purge $_p"; }; done; }
# ENTRY: the entry's sorted dist-info names, the R3 listing.
distinfo() {
    for _d in "$1"/lib/*/site-packages/*.dist-info "$1"/*.dist-info; do
        [ -d "$_d" ] || continue; _b=${_d##*/}; echo "${_b%.dist-info}"
    done | LC_ALL=C sort
}
base_sp() { for _d in "$root"/python/cpython-3.12.*/; do [ -L "${_d%/}" ] || { echo "${_d}lib/python3.12/site-packages"; return; }; done; }
# Every path under UVM_ROOT with its type and size, sorted: a write shows.
treelist() { find "$UVM_ROOT" -exec ls -ldn {} + | awk '{ print $1, $5, $NF }' | LC_ALL=C sort -k3; }
# LABEL VALUE CMD...: one knob-set call; its rc, stdout and stderr under $o.
knob() {
    _l="$1" _v="$2"; shift 2
    ( UVM_REPAIR="$_v"; UVM_LOCK_TIMEOUT=180; export UVM_REPAIR UVM_LOCK_TIMEOUT; "$@" ) > "$o/$_l.out" 2> "$o/$_l.err"
    echo $? > "$o/$_l.rc"
}
rc() { cat "$o/$1.rc"; }
said() { grep -c "$2" "$o/$1.err" | tr -d ' '; }
# What each subject's call prints, and the call itself.
call() {
    case "$1" in
        script) set -- uv run --no-project "$w/s.py" ;; new) set -- uv run --no-project "$w/n.py" ;;
        uvx) set -- uvx tqdm==4.67.1 --version ;; flake8) set -- uvx flake8==7.1.1 --version ;;
        ruff) set -- uvx ruff==0.8.4 --version ;;
    esac
    "$@"
}
expect() {
    case "$1" in
        script) [ "$2" = "s ok 4.67.1" ] ;; new) [ "$2" = "n ok 4.67.1" ] ;; uvx) [ "$2" = 4.67.1 ] ;;
        flake8) case "$2" in "7.1.1 (mccabe: 0.7.0, pycodestyle: 2.12.1, pyflakes: 3.2.0) CPython 3.12."*) ;; *) false ;; esac ;;
        ruff) [ "$2" = "ruff 0.8.4" ] ;;
    esac
}
archives() { ls "$c/archive-v0" | wc -l | tr -d ' '; }
envlinks() { find "$c/environments-v2" -type l | grep -vc '/bin/\|/lib64$' | tr -d ' '; }
