#!/bin/sh
# SPDX-FileCopyrightText: 2026 Geoffrey Lentner
# SPDX-License-Identifier: MIT
#
# Release concurrent ranks at a damaged tree with UVM_REPAIR=1, and check that
# exactly one repairs it under the repair lock while the rest wait and then run.
#
#   tests/repair-race.sh --scenario F|T|P|kill [--ranks N] [--timeout S]
#                        [--launch local|srun] [--summary FILE]
#                        [--uv-bin PATH] [--uv-version VER]
#
# Each scenario prepares one tree in a temp_root.sh sandbox, damages it, and
# releases the ranks at it once. Every rank makes one wrapper call with
# UVM_REPAIR=1 and UVM_LOCK_TIMEOUT set to --timeout.
#
#   F     The offline fixture. A planted tool whose RECORD names an absent file,
#         and a stub repair that takes 3 s. Each rank runs `uv --version`.
#   T     Real uv, a managed cpython 3.12, and two tools damaged the way a
#         purge damages them, a module file and the RECORD manifests moved out:
#         pyflakes pinned at 3.2.0, and beside it pycodestyle installed at
#         2.11.1 with six 1.16.0, then installed again unpinned, so its receipt
#         names no version while newer releases of both exist. Each rank runs
#         `uvx pyflakes --version`, and the unpinned tool must come back at
#         exactly the versions it had, with its receipt unchanged.
#   P     Real uv and a managed cpython 3.12 with every file removed and its
#         directories and links kept, the shape an access-time purge leaves on
#         an idle interpreter. Each rank runs `uv run --no-project -p 3.12` on a
#         script that imports json.
#   kill  As P, and the rank whose own wrapper holds the repair lock kills it
#         with KILL on sight. Every other rank must fail at the timeout naming
#         the lock, and no outcome may be recorded. `uvm doctor` must then
#         report the lock, `uvm clean lock --yes` removes it, and a clean pass
#         in the same scope must repair once with every rank exiting 0.
#
# --timeout S     the ranks' UVM_LOCK_TIMEOUT: 180 by default, 20 under kill.
# --uv-bin PATH   seeds versions/<ver> and `current` from a local uv binary and
#                 the uvx beside it, for a host where the installer cannot run.
#                 Without it, the job sets UVM_PIN to --uv-version (default
#                 0.13.6) and the wrapper provisions through the real installer,
#                 which is the cluster path. The pin fixes the interpreter too:
#                 uv embeds its download list, so one uv version resolves 3.12
#                 to one patch everywhere.
# --launch srun   starts the ranks with srun inside a Slurm allocation, as
#                 tests/lock-race.sh does. REPAIRRACE_SHARED must name a
#                 directory on the filesystem under test, and becomes TMPDIR,
#                 so the sandbox and the collection directory both go there.
#                 The checkout must be on a filesystem every node mounts,
#                 because the ranks re-execute this file by its path.
# --summary FILE  writes the result block to FILE as well as stdout.
#
# The real scenarios need egress: astral.sh and its binary host for uv unless
# --uv-bin is given, releases.astral.sh for the interpreter, and pypi.org and
# files.pythonhosted.org for the tool. A host that is missing shows as a
# preparation failure (exit 4) or as a failed outcome.
#
# The kill. Each rank starts its wrapper call directly in the background, so $!
# is the wrapper's own pid, which is the pid its owner line records; started
# through a compound command, $! names a subshell and never matches. A watcher
# beside it reads the lock's owner line every 0.1 s, and the one rank that
# reads `host=<its node> pid=<its wrapper>` kills that wrapper. No signal
# crosses a node and no process listing is needed: the holder's own rank runs
# on the holder's node.
#
# The kill takes the wrapper's process group, which is the wrapper and every
# child it started, as a node fault would. Killing the wrapper alone was
# measured to fail the scenario: the holder had already started its
# interpreter reinstall, which ran on unrecorded and restored the tree before
# the clean pass, so the clean pass had nothing to repair. The wrapper gets a
# group of its own from job control (`set -m`), which dash refuses without a
# terminal, so the job and the ranks run under bash. The wrapper needs bash, so
# every node that runs it has one. The scenario damages the interpreter, whose
# download outlasts a kill on sight, rather than a tool, whose rebuild did not.
#
# The result block is key=value lines of counts, whole seconds, version numbers
# and fixed words, and nothing else: no hostname, username, path or date. A
# cluster run's summary is committed to a public repository as evidence. Node
# names are reduced to their count here and go no further. Never keep a
# sandbox from a cluster run.
#
#   repairs        ranks that announced a repair arm, the killed rank excepted
#   repair_lines   announcements across all ranks
#   hold_s         the repairing rank's elapsed seconds
#   wait_max_s, wait_p50_s   the other ranks' elapsed seconds
#   notice_lines   the repair lock's once-per-wait notices across all ranks
#   timeout_named_lock   ranks that failed at the timeout naming the repair lock
#   outcomes, outcome_kind   the records left for the scope
#   locks_left     lock directories standing after the pass
#   restored       whether the damaged files are back (na for the fixture)
#
# T adds what the unpinned tool came back as, and whether anything moved:
#
#   unpinned_version, unpinned_with   pycodestyle's and its six's versions
#   second_dist_info   distributions with more than one dist-info directory
#   receipts_kept      tools whose uv-receipt.toml is byte-identical to before
#
# Under kill the killed pass reports those keys, then doctor_warn_repair_lock,
# then the clean pass's keys prefixed clean_.
#
# Exit 0  every check of the scenario held.
# Exit 1  a correctness defect; stderr names the key that caught it.
# Exit 2  usage.
# Exit 4  the drive never constructed the scenario: preparation failed, srun
#         failed to launch, or no rank killed the holder. The correctness keys
#         then mean nothing.

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
repo=$(CDPATH='' cd -- "$here/.." && pwd -P)
self="$here/$(basename -- "$0")"

# ---- rank: one wrapper call -------------------------------------------------
#
# The uv on PATH must be the wrapper under test. temp_root.sh puts this
# checkout's bin/ first, but a compute node can carry a user-installed uv, and a
# launch environment that reordered PATH would run that one and report its
# answers as the wrapper's. Such a rank runs nothing and records `nowrapper` as
# its status, so it can only ever count against the run.

# PID MARK: kill PID's process group once the repair lock's owner line names
# PID on this node. MARK records what the kill took: the group, or the wrapper
# alone where the shell gave it no group of its own.
killwatch() {
    _me="host=$(uname -n) pid=$1"
    while :; do
        _o=''
        { read -r _o < "$REPAIRRACE_OWNER"; } 2>/dev/null
        if [ "$_o" = "$_me" ]; then
            if kill -KILL "-$1" 2>/dev/null; then echo group > "$2"
            elif kill -KILL "$1" 2>/dev/null; then echo wrapper > "$2"
            fi
            return 0
        fi
        # Another rank's wrapper holds the lock, and under kill it never
        # releases, so this rank's wrapper will not hold it.
        [ -z "$_o" ] || return 0
        sleep 0.1 2>/dev/null || sleep 1
    done
}

rank() {
    _i="$1"
    _d="$REPAIRRACE_COLLECT/$REPAIRRACE_PASS"
    if [ "$(command -v uv)" = "$repo/bin/uv" ]; then
        case "$REPAIRRACE_SCENARIO" in
            F) set -- uv --version ;;
            T) set -- uvx pyflakes --version ;;
            *) set -- uv run --no-project -p 3.12 "$REPAIRRACE_COLLECT/t.py" ;;
        esac
        UVM_REPAIR=1 UVM_LOCK_TIMEOUT="$REPAIRRACE_TIMEOUT"
        export UVM_REPAIR UVM_LOCK_TIMEOUT
        _kill=''
        [ "$REPAIRRACE_SCENARIO" != kill ] || [ "$REPAIRRACE_PASS" != main ] || _kill=1
        # Job control only for the call the kill may take: it puts the wrapper
        # in a process group of its own, whose id is the wrapper's pid.
        [ -z "$_kill" ] || set -m
        _s0=$(date +%s)
        "$@" > "$_d/out.$_i" 2> "$_d/err.$_i" &
        _pid=$!
        _watch=''
        if [ -n "$_kill" ]; then
            set +m
            killwatch "$_pid" "$_d/killed.$_i" &
            _watch=$!
        fi
        wait "$_pid"
        _rc=$?
        _s1=$(date +%s)
        if [ -n "$_watch" ]; then
            kill "$_watch" 2>/dev/null
            wait "$_watch" 2>/dev/null
        fi
        echo "$_rc" > "$_d/rc.$_i"
        echo "$((_s1 - _s0))" > "$_d/el.$_i"
        _w=wrapper
    else
        echo nowrapper > "$_d/rc.$_i"
        _w=other
    fi
    # Recorded after the call, so these forks do not spread the ranks' arrival.
    # shellcheck disable=SC2016  # expanded by the inner bash, not this shell
    _b=$(bash -c 'printf "%s.%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null) || _b=''
    printf '%s %s %s\n' "$(uname -n)" "${_b:-none}" "$_w" > "$_d/who.$_i"
}

if [ "${REPAIRRACE_ROLE:-}" = rank ]; then
    : "${SLURM_PROCID:?a rank re-executed by srun needs SLURM_PROCID}"
    rank "$((SLURM_PROCID + 1))"
    exit 0
fi

# ---- job: prepare, damage, release, record ----------------------------------
#
# Runs inside the sandbox, which temp_root.sh removes when it exits, so every
# fact the driver reports is written to the collection directory first.

fact() { printf '%s=%s\n' "$1" "$2" >> "$REPAIRRACE_COLLECT/facts"; }
# Ends the job with a fixed phrase in place of an outcome. Its detail is in
# prep.err, which names paths and so never reaches the summary.
noprep() { fact prep "$1"; exit 0; }

# The non-symlink cpython 3.12 directory: uv installs a minor-version symlink
# beside it.
interp() {
    _base=''
    for _e in "$root"/python/cpython-3.12.*/; do
        [ -d "$_e" ] && [ ! -L "${_e%/}" ] && _base="${_e%/}"
    done
    echo "$_base"
}

restored() {
    case "$REPAIRRACE_SCENARIO" in
        F) echo na ;;
        T)
            _sp="$root/tools/pyflakes/lib/python3.12/site-packages"
            _sq="$root/tools/pycodestyle/lib/python3.12/site-packages"
            if [ -f "$_sp/pyflakes/checker.py" ] && ls "$_sp"/pyflakes-*.dist-info/RECORD > /dev/null 2>&1 &&
               [ -f "$_sq/pycodestyle.py" ] && ls "$_sq"/pycodestyle-*.dist-info/RECORD "$_sq"/six-*.dist-info/RECORD > /dev/null 2>&1
            then echo 1; else echo 0; fi ;;
        *)
            _base=$(interp)
            if [ -n "$_base" ] && "$_base/bin/python3" -c 'import json, os, ssl' > /dev/null 2>&1
            then echo 1; else echo 0; fi ;;
    esac
}

prepare_fixture() {
    uv --version > /dev/null 2>> "$c/prep.err" || noprep "provisioning the fixture failed"
    fact uv "$(uv --version 2>/dev/null | awk '{ print $2 }')"
    _sp="$root/tools/fx/lib/python3.12/site-packages"
    mkdir -p "$_sp/fx-1.0.dist-info" "$root/tools/fx/bin"
    # The tool arm reinstalls only into an environment whose interpreter runs.
    ln -s /bin/sh "$root/tools/fx/bin/python"
    : > "$root/tools/fx/pyvenv.cfg"
    : > "$root/tools/fx/uv-receipt.toml"
    printf 'fx/__init__.py,,\n' > "$_sp/fx-1.0.dist-info/RECORD"
    # Holds the repair lock past several of a waiter's one-second polls.
    UVM_FIXTURE_REPAIR_SLEEP=3
    export UVM_FIXTURE_REPAIR_SLEEP
}

prepare_real() {
    # User policy rather than the wrapper's, so the interpreter and the tool's
    # environment both live in the sandbox.
    UV_PYTHON_PREFERENCE=only-managed
    export UV_PYTHON_PREFERENCE
    if [ -n "$REPAIRRACE_UV_BIN" ]; then
        _v=$("$REPAIRRACE_UV_BIN" --version 2>/dev/null | awk '{ print $2 }')
        [ -n "$_v" ] || noprep "the seed uv does not run"
        { mkdir -p "$root/versions/$_v" &&
          cp "$REPAIRRACE_UV_BIN" "$root/versions/$_v/uv" &&
          cp "$(dirname -- "$REPAIRRACE_UV_BIN")/uvx" "$root/versions/$_v/uvx" &&
          ln -s "versions/$_v" "$root/current"; } 2>> "$c/prep.err" || noprep "seeding uv failed"
    else
        UVM_PIN="$REPAIRRACE_UV_VERSION"
        export UVM_PIN
    fi
    _v=$(uv --version 2>> "$c/prep.err" | awk '{ print $2 }')
    [ -n "$_v" ] || noprep "provisioning uv failed"
    [ -n "$REPAIRRACE_UV_BIN" ] || [ "$_v" = "$REPAIRRACE_UV_VERSION" ] \
        || noprep "the provisioned uv is not the pinned version"
    fact uv "$_v"
    uv python install 3.12 >> "$c/prep.err" 2>&1 || noprep "the interpreter install failed"
    case "$REPAIRRACE_SCENARIO" in
        T)
            { uv tool install pyflakes==3.2.0 --python 3.12 &&
              uv tool install pycodestyle==2.11.1 --with six==1.16.0 --python 3.12 &&
              uv tool install pycodestyle --with six --python 3.12; } >> "$c/prep.err" 2>&1 \
                || noprep "the tool install failed"
            _sq="$root/tools/pycodestyle/lib/python3.12/site-packages"
            if [ "$(unpinned)" != "2.11.1 1.16.0" ] ||
               ! grep -q '{ name = "pycodestyle" }' "$root/tools/pycodestyle/uv-receipt.toml"; then
                noprep "the unpinned tool is not at its older release"
            fi
            for _t in pyflakes pycodestyle; do
                cp "$root/tools/$_t/uv-receipt.toml" "$c/receipt.$_t" 2>> "$c/prep.err" || noprep "the receipts could not be kept"
            done
            _sp="$root/tools/pyflakes/lib/python3.12/site-packages"
            # One mv per file, each to a destination named for it. Three of
            # these files are named RECORD: GNU mv refuses to overwrite a file
            # it created earlier in the same call, and BSD mv overwrites it
            # silently, so neither may see two sources with one name.
            { mv "$_sp/pyflakes/checker.py" "$trash/pyflakes.checker.py" &&
              mv "$_sp"/pyflakes-*.dist-info/RECORD "$trash/pyflakes.RECORD" &&
              mv "$_sq/pycodestyle.py" "$trash/pycodestyle.pycodestyle.py" &&
              mv "$_sq"/pycodestyle-*.dist-info/RECORD "$trash/pycodestyle.RECORD" &&
              mv "$_sq"/six-*.dist-info/RECORD "$trash/six.RECORD"; } 2>> "$c/prep.err" \
                || noprep "the damage could not be made"
            if uvx pyflakes --version > /dev/null 2>&1; then
                noprep "the damage did not break the command"
            fi ;;
        *)
            _base=$(interp)
            [ -n "$_base" ] || noprep "no managed interpreter directory"
            find "$_base" -type f -delete 2>> "$c/prep.err" || noprep "the damage could not be made"
            [ -d "$_base/lib/python3.12" ] && [ -z "$(find "$_base" -type f)" ] \
                || noprep "the damage could not be made"
            printf 'import json\nprint("t-ok", json.dumps([1]))\n' > "$c/t.py"
            if uv run --no-project -p 3.12 "$c/t.py" > /dev/null 2>&1; then
                noprep "the damage did not break the command"
            fi ;;
    esac
}

# The unpinned tool's version and its six's, from their dist-info names, and
# the distributions in either damaged tool with a second dist-info directory.
unpinned() {
    _sq="$root/tools/pycodestyle/lib/python3.12/site-packages"
    _a='' _b=''
    for _e in "$_sq"/pycodestyle-*.dist-info; do
        [ -d "$_e" ] || continue
        _e="${_e##*/pycodestyle-}"; _a="${_a:+$_a,}${_e%.dist-info}"
    done
    for _e in "$_sq"/six-*.dist-info; do
        [ -d "$_e" ] || continue
        _e="${_e##*/six-}"; _b="${_b:+$_b,}${_e%.dist-info}"
    done
    echo "${_a:-none} ${_b:-none}"
}
second_dist_info() {
    for _t in pyflakes pycodestyle; do
        ( cd "$root/tools/$_t/lib/python3.12/site-packages" 2>/dev/null && ls -d ./*.dist-info ) | sed 's/-[^-]*\.dist-info$//'
    done | sort | uniq -d | wc -l | tr -d ' '
}
receipts_kept() {
    _n=0
    for _t in pyflakes pycodestyle; do
        ! cmp -s "$c/receipt.$_t" "$root/tools/$_t/uv-receipt.toml" || _n=$((_n + 1))
    done
    echo "$_n"
}

# NAME: release every rank once, then record what the pass left.
run_pass() {
    REPAIRRACE_PASS="$1"
    export REPAIRRACE_PASS
    _pd="$c/$1"
    mkdir -p "$_pd"
    _lf=0
    _s0=$(date +%s)
    case "$REPAIRRACE_LAUNCH" in
        srun)
            # --export=ALL carries the sandbox's environment to every node:
            # PATH with this checkout's bin/ first, UVM_ROOT, the pin and the
            # knobs above. srun's own words stay in the collection directory,
            # because they can name nodes.
            REPAIRRACE_ROLE=rank srun --ntasks="$REPAIRRACE_RANKS" --kill-on-bad-exit=0 \
                --distribution=cyclic --cpu-bind=none --export=ALL \
                bash "$self" > /dev/null 2> "$_pd/srun.err" || _lf=1
            ;;
        *)
            _i=1
            _pids=''
            while [ "$_i" -le "$REPAIRRACE_RANKS" ]; do
                ( rank "$_i" ) &
                _pids="$_pids $!"
                _i=$((_i + 1))
            done
            # shellcheck disable=SC2086  # a list of pids, split on purpose
            wait $_pids
            ;;
    esac
    _s1=$(date +%s)
    _n=0
    _kind=none
    for _f in "$root"/.repair/*; do
        [ -e "$_f" ] || continue
        _n=$((_n + 1))
        case "$_f" in *.ok) _k=ok ;; *.failed) _k=failed ;; *) _k=other ;; esac
        if [ "$_n" -eq 1 ]; then _kind="$_k"; else _kind=mixed; fi
    done
    _l=0
    for _k in install repair; do
        [ ! -d "$root/.$_k.lock" ] || _l=$((_l + 1))
    done
    printf '%s\n' "wall=$((_s1 - _s0))" "outcomes=$_n" "outcome_kind=$_kind" \
        "locks_left=$_l" "restored=$(restored)" "launch_failures=$_lf" > "$_pd/facts"
    if [ "$REPAIRRACE_SCENARIO" = T ]; then
        # Two words, split on purpose.
        # shellcheck disable=SC2046
        set -- $(unpinned)
        printf '%s\n' "unpinned_version=$1" "unpinned_with=$2" \
            "second_dist_info=$(second_dist_info)" "receipts_kept=$(receipts_kept)" >> "$_pd/facts"
    fi
}

if [ "${REPAIRRACE_ROLE:-}" = job ]; then
    : "${UVM_ROOT:?}" "${UVM_SANDBOX:?}" "${REPAIRRACE_COLLECT:?}" "${REPAIRRACE_SCENARIO:?}"
    : "${REPAIRRACE_RANKS:?}" "${REPAIRRACE_TIMEOUT:?}" "${REPAIRRACE_LAUNCH:?}"
    : "${REPAIRRACE_UV_VERSION:?}" "${REPAIRRACE_UV_BIN=}"
    c="$REPAIRRACE_COLLECT"
    root="$UVM_ROOT/${UVM_PLATFORM:-$(uname -m)}"
    # Damage to a tool is a move into this directory. Damage to the interpreter
    # removes every file and keeps every directory and link, as a purge does.
    trash="$UVM_SANDBOX/trash"
    mkdir -p "$trash"
    REPAIRRACE_OWNER="$root/.repair.lock/owner"
    export REPAIRRACE_OWNER
    p0=$(date +%s)
    case "$REPAIRRACE_SCENARIO" in
        F) prepare_fixture ;;
        *) prepare_real ;;
    esac
    fact prep_s "$(($(date +%s) - p0))"
    fact prep ok
    run_pass main
    if [ "$REPAIRRACE_SCENARIO" = kill ]; then
        uvm doctor > "$c/doctor.out" 2>&1
        fact doctor_warn_repair_lock "$(grep -c '^WARN  repair lock standing' "$c/doctor.out")"
        uvm clean lock --yes > /dev/null 2>&1 || fact clean_lock failed
        run_pass clean
    fi
    exit 0
fi

# ---- driver -----------------------------------------------------------------

scenario='' ranks=64 timeout='' launch=local summary='' uv_bin='' uv_version=0.13.6

usage() { echo "repair-race.sh: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --scenario)   scenario="${2:?--scenario needs F, T, P or kill}"; shift 2 ;;
        --ranks)      ranks="${2:?--ranks needs a count}"; shift 2 ;;
        --timeout)    timeout="${2:?--timeout needs seconds}"; shift 2 ;;
        --launch)     launch="${2:?--launch needs local|srun}"; shift 2 ;;
        --summary)    summary="${2:?--summary needs a file}"; shift 2 ;;
        --uv-bin)     uv_bin="${2:?--uv-bin needs a path}"; shift 2 ;;
        --uv-version) uv_version="${2:?--uv-version needs a version}"; shift 2 ;;
        *) usage "unknown option: $1" ;;
    esac
done
case "$scenario" in F|T|P|kill) ;; *) usage "--scenario must be F, T, P or kill" ;; esac
case "$launch" in local|srun) ;; *) usage "bad --launch: $launch (local or srun)" ;; esac
case "$ranks" in ''|*[!0-9]*|0) usage "bad --ranks: $ranks (a positive count)" ;; esac
if [ -z "$timeout" ]; then
    if [ "$scenario" = kill ]; then timeout=20; else timeout=180; fi
fi
case "$timeout" in ''|*[!0-9]*) usage "bad --timeout: $timeout (whole seconds)" ;; esac
case "$uv_version" in ''|*[!0-9.]*|.*|*.) usage "bad --uv-version: $uv_version (a version such as 0.13.6)" ;; esac
if [ -n "$uv_bin" ]; then
    [ "$scenario" != F ] || usage "--uv-bin applies to T, P and kill; F uses the fixture"
    case "$uv_bin" in /*) ;; *) uv_bin="$(pwd -P)/$uv_bin" ;; esac
    [ -x "$uv_bin" ] && [ -x "$(dirname -- "$uv_bin")/uvx" ] \
        || usage "--uv-bin must name an executable uv with uvx beside it: $uv_bin"
fi
if [ "$launch" = srun ]; then
    if [ -z "${REPAIRRACE_SHARED:-}" ] || [ ! -d "$REPAIRRACE_SHARED" ]; then
        usage "--launch srun needs REPAIRRACE_SHARED to name a directory on the filesystem under test"
    fi
    command -v srun > /dev/null 2>&1 || usage "--launch srun needs srun on PATH, inside a Slurm allocation"
    TMPDIR="$REPAIRRACE_SHARED"
    export TMPDIR
fi
if [ -n "$summary" ]; then
    # Emptied now, so a run that stops before its result block cannot leave an
    # earlier run's summary standing under its name.
    : > "$summary" || usage "cannot write --summary $summary"
fi

temp_root="$repo/.agents/factory/bin/temp_root.sh"
[ -x "$temp_root" ] || usage "missing $temp_root"

# The wrapper's answers are compared as text, and strerror text is localized.
LC_ALL=C
export LC_ALL

c=$(mktemp -d "${TMPDIR:-/tmp}/uvm-repairrace.XXXXXX") || usage "cannot create a collection directory"
trap 'rm -rf "$c"' EXIT
trap 'exit 130' INT TERM

runjob() {
    if [ "$scenario" = F ]; then "$temp_root" --offline "$@"; else "$temp_root" "$@"; fi
}
REPAIRRACE_ROLE=job REPAIRRACE_COLLECT="$c" REPAIRRACE_SCENARIO="$scenario" \
REPAIRRACE_RANKS="$ranks" REPAIRRACE_TIMEOUT="$timeout" REPAIRRACE_LAUNCH="$launch" \
REPAIRRACE_UV_BIN="$uv_bin" REPAIRRACE_UV_VERSION="$uv_version" \
    runjob bash "$self" > "$c/job.log" 2>&1
jrc=$?

# KEY FILE DEFAULT: the last value of KEY in a key=value file.
val() { _v=$(sed -n "s/^$1=//p" "$2" 2>/dev/null | tail -n 1); echo "${_v:-$3}"; }
# One value per line on stdin, as value:count pairs joined by commas.
hist() { sort | uniq -c | awk '{ printf "%s%s:%s", (NR > 1 ? "," : ""), $2, $1 } END { print "" }'; }
nz() { case "$1" in ''|*[!0-9]*) echo 0 ;; *) echo "$1" ;; esac; }

case "$scenario" in
    F) want=9.9.9 ;;
    T) want=3.2.0 ;;
    *) want=expected ;;
esac

# A rank's stdout, as one word: the version it printed, `expected` for the
# script's line, `none` when empty, and `other` for anything else, so a uv that
# is not the wrapper under test cannot pass for it.
classify() {
    _o=$(cat "$1" 2>/dev/null)
    if [ -z "$_o" ]; then echo none; return; fi
    [ "$(printf '%s\n' "$_o" | wc -l | tr -d ' ')" = 1 ] || { echo other; return; }
    case "$scenario" in
        F)
            case "$_o" in
                "uv "*" (fixture)") _o="${_o#uv }"; _o="${_o% (fixture)}" ;;
                *) _o='' ;;
            esac ;;
        T)
            case "$_o" in
                *" Python 3.12."*) _o="${_o%% *}" ;;
                *) _o='' ;;
            esac ;;
        *)
            if [ "$_o" = 't-ok [1]' ]; then _o=expected; else _o=''; fi ;;
    esac
    case "$_o" in ''|*[!0-9a-z.]*) echo other ;; *) echo "$_o" ;; esac
}

# PASS PREFIX: the pass's keys, each prefixed.
reduce() {
    _d="$c/$1"
    _p="$2"
    for _h in rc out node bash path wait took; do : > "$c/h.$_h"; done
    _rep=0 _lines=0 _notice=0 _tnl=0 _killed=0 _holder=''
    _i=1
    while [ "$_i" -le "$ranks" ]; do
        _r=$(cat "$_d/rc.$_i" 2>/dev/null)
        echo "${_r:-none}" >> "$c/h.rc"
        classify "$_d/out.$_i" >> "$c/h.out"
        _e="$_d/err.$_i"
        _a=$(nz "$(grep -c 'uv-manager: repairing the ' "$_e" 2>/dev/null)")
        _lines=$((_lines + _a))
        _k=0
        if [ -e "$_d/killed.$_i" ]; then
            _k=1
            _killed=$((_killed + 1))
            cat "$_d/killed.$_i" >> "$c/h.took"
        fi
        if [ "$_a" -gt 0 ] && [ "$_k" -eq 0 ]; then _rep=$((_rep + 1)); _holder="$_i"; fi
        _notice=$((_notice + $(nz "$(grep -c 'uv-manager: waiting for the repair lock' "$_e" 2>/dev/null)")))
        if grep -q "timed out after ${timeout}s waiting for the repair lock" "$_e" 2>/dev/null; then
            _tnl=$((_tnl + 1))
        fi
        # node, bash version, wrapper|other: three words, split on purpose.
        _who=$(cat "$_d/who.$_i" 2>/dev/null) || _who=''
        # shellcheck disable=SC2086
        set -- $_who
        echo "${1:-none}" >> "$c/h.node"
        echo "${2:-none}" >> "$c/h.bash"
        echo "${3:-none}" >> "$c/h.path"
        _i=$((_i + 1))
    done
    _hold=none
    if [ "$_rep" -eq 1 ]; then _hold=$(nz "$(cat "$_d/el.$_holder" 2>/dev/null)"); fi
    _i=1
    while [ "$_i" -le "$ranks" ]; do
        if [ "$_i" != "$_holder" ] && [ ! -e "$_d/killed.$_i" ] && [ -s "$_d/el.$_i" ]; then
            cat "$_d/el.$_i" >> "$c/h.wait"
        fi
        _i=$((_i + 1))
    done
    _nw=$(wc -l < "$c/h.wait" | tr -d ' ')
    if [ "$_nw" -gt 0 ]; then
        _wmax=$(sort -n "$c/h.wait" | tail -n 1)
        _wp50=$(sort -n "$c/h.wait" | sed -n "$(((_nw + 1) / 2))p")
    else
        _wmax=none _wp50=none
    fi
    _took=$(sort -u "$c/h.took" | paste -s -d , -)
    _f="$_d/facts"
    printf '%s\n' \
        "wall=$(val wall "$_f" none)" \
        "rc_hist=$(hist < "$c/h.rc")" \
        "stdout_hist=$(hist < "$c/h.out")" \
        "uv_resolved=$(hist < "$c/h.path")" \
        "nodes=$(grep -v -x none "$c/h.node" | sort -u | wc -l | tr -d ' ')" \
        "bash=$(grep -v -x none "$c/h.bash" | sort -u | paste -s -d , -)" \
        "repairs=$_rep" "repair_lines=$_lines" \
        "hold_s=$_hold" "wait_max_s=$_wmax" "wait_p50_s=$_wp50" \
        "notice_lines=$_notice" "timeout_named_lock=$_tnl" "killed=$_killed" \
        "kill_took=${_took:-none}" \
        "outcomes=$(val outcomes "$_f" none)" "outcome_kind=$(val outcome_kind "$_f" none)" \
        "locks_left=$(val locks_left "$_f" none)" "restored=$(val restored "$_f" none)" \
        "launch_failures=$(val launch_failures "$_f" none)" | sed "s/^/$_p/"
    if [ "$scenario" = T ]; then
        printf '%s\n' "unpinned_version=$(val unpinned_version "$_f" none)" \
            "unpinned_with=$(val unpinned_with "$_f" none)" \
            "second_dist_info=$(val second_dist_info "$_f" none)" \
            "receipts_kept=$(val receipts_kept "$_f" none)" | sed "s/^/$_p/"
    fi
}

prep=$(val prep "$c/facts" "did not finish")
{
    printf '%s\n' "scenario=$scenario" "launch=$launch" "ranks=$ranks" "timeout=$timeout" \
        "uv=$(val uv "$c/facts" none)" "prep_s=$(val prep_s "$c/facts" none)"
    if [ "$prep" = ok ]; then
        reduce main ''
        if [ "$scenario" = kill ]; then
            echo "doctor_warn_repair_lock=$(val doctor_warn_repair_lock "$c/facts" none)"
            reduce clean clean_
        fi
    fi
} > "$c/result"

key() { val "$1" "$c/result" none; }

progress=ok
if [ "$jrc" -ne 0 ]; then
    progress="the job role exited $jrc"
elif [ "$prep" != ok ]; then
    progress="preparation failed: $prep"
elif [ "$(key launch_failures)" != 0 ] || [ "$(key clean_launch_failures)" = 1 ]; then
    progress="srun failed to launch the ranks"
elif [ "$scenario" = kill ] && [ "$(key killed)" != 1 ]; then
    progress="$(key killed) ranks killed their own wrapper holding the repair lock, so the fault was not constructed"
fi
echo "progress=$progress" >> "$c/result"
cat "$c/result"
[ -z "$summary" ] || cp "$c/result" "$summary"

if [ "$progress" != ok ]; then
    echo "repair-race.sh: the drive did not construct the scenario -- this is not a race result" >&2
    # The job's own output and srun's words go to stderr only: they name paths
    # and nodes, and the result block is meant for a public repository.
    for f in "$c/job.log" "$c/prep.err" "$c"/*/srun.err; do
        [ -s "$f" ] || continue
        echo "repair-race.sh: ${f##*/}:" >&2
        tail -n 20 "$f" | sed 's/^/    /' >&2
    done
    exit 4
fi

rc=0
bad() { echo "repair-race.sh: FAIL $*" >&2; rc=1; }
# PREFIX: the checks every pass that must repair shares.
repaired() {
    [ "$(key "${1}rc_hist")" = "0:$ranks" ]          || bad "${1}rc_hist=$(key "${1}rc_hist"): not every rank exited 0"
    [ "$(key "${1}stdout_hist")" = "$want:$ranks" ]  || bad "${1}stdout_hist=$(key "${1}stdout_hist"): expected $want:$ranks"
    [ "$(key "${1}uv_resolved")" = "wrapper:$ranks" ] || bad "${1}uv_resolved=$(key "${1}uv_resolved"): a rank ran another uv"
    [ "$(key "${1}repairs")" = 1 ]                   || bad "${1}repairs=$(key "${1}repairs"): expected exactly 1"
    [ "$(key "${1}outcomes")" = 1 ] && [ "$(key "${1}outcome_kind")" = ok ] \
        || bad "${1}outcomes=$(key "${1}outcomes") ${1}outcome_kind=$(key "${1}outcome_kind"): expected one repaired outcome"
    [ "$(key "${1}locks_left")" = 0 ]                || bad "${1}locks_left=$(key "${1}locks_left"): a lock was left standing"
    case "$(key "${1}restored")" in 1|na) ;; *) bad "${1}restored=$(key "${1}restored"): the damage is still there" ;; esac
    if [ "$scenario" = T ]; then
        [ "$(key "${1}unpinned_version")" = 2.11.1 ] || bad "${1}unpinned_version=$(key "${1}unpinned_version"): the unpinned tool moved"
        [ "$(key "${1}unpinned_with")" = 1.16.0 ]    || bad "${1}unpinned_with=$(key "${1}unpinned_with"): its --with package moved"
        [ "$(key "${1}second_dist_info")" = 0 ]      || bad "${1}second_dist_info=$(key "${1}second_dist_info"): a second dist-info was left"
        [ "$(key "${1}receipts_kept")" = 2 ]         || bad "${1}receipts_kept=$(key "${1}receipts_kept"): a receipt changed"
    fi
}
if [ "$scenario" = kill ]; then
    w=$((ranks - 1))
    if [ "$w" -gt 0 ]; then want_rc="1:$w,137:1"; else want_rc="137:1"; fi
    [ "$(key rc_hist)" = "$want_rc" ]          || bad "rc_hist=$(key rc_hist): expected $want_rc"
    [ "$(key timeout_named_lock)" = "$w" ]     || bad "timeout_named_lock=$(key timeout_named_lock): expected $w"
    [ "$(key repairs)" = 0 ]                   || bad "repairs=$(key repairs): a waiter repaired"
    [ "$(key outcomes)" = 0 ]                  || bad "outcomes=$(key outcomes): the killed holder recorded an outcome"
    [ "$(key locks_left)" = 1 ]                || bad "locks_left=$(key locks_left): expected the killed holder's lock"
    [ "$(key doctor_warn_repair_lock)" = 1 ]   || bad "doctor_warn_repair_lock=$(key doctor_warn_repair_lock): expected 1"
    repaired clean_
else
    repaired ''
fi
exit "$rc"
