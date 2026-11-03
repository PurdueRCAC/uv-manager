# sourced inside temp_root.sh (bash). Seeds real uv, sets policy.
set -u
UV_PYTHON_PREFERENCE=only-managed; export UV_PYTHON_PREFERENCE
XDG_DATA_HOME="$UVM_SANDBOX/xdg"; export XDG_DATA_HOME
UVB="${SEED_DIR:?set SEED_DIR to the directory holding a real uv and uvx}"
a=${UVM_PLATFORM:-$(uname -m)}
root="$UVM_ROOT/$a"; c="$root/cache"
seed() { local v; v=$("$UVB/uv" --version | awk '{print $2}')
  mkdir -p "$root/versions/$v" && cp "$UVB/uv" "$UVB/uvx" "$root/versions/$v/" && ln -sfn "versions/$v" "$root/current"; }
W="$UVM_SANDBOX/work"; mkdir -p "$W"
mk() { cat > "$1" <<P
# /// script
# requires-python = ">=3.12"
# dependencies = [$2]
# ///
$3
P
}
