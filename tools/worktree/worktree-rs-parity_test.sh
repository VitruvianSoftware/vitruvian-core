#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# worktree-rs-parity_test.sh — side-by-side behavioural parity test between
# worktree.sh and the Rust port across normal and edge-case scenarios.
set -uo pipefail

SH_BIN="${1:?usage: worktree-rs-parity_test.sh <worktree.sh> <worktree-rs> <landed.sh>}"
SH_BIN="$(cd "$(dirname "$SH_BIN")" && pwd -P)/$(basename "$SH_BIN")"
RS_BIN="${2:?usage: worktree-rs-parity_test.sh <worktree.sh> <worktree-rs> <landed.sh>}"
RS_BIN="$(cd "$(dirname "$RS_BIN")" && pwd -P)/$(basename "$RS_BIN")"
REAL_LANDED="${3:?usage: worktree-rs-parity_test.sh <worktree.sh> <worktree-rs> <landed.sh>}"
REAL_LANDED="$(cd "$(dirname "$REAL_LANDED")" && pwd -P)/$(basename "$REAL_LANDED")"

REAL_GIT="$(command -v git)"
REAL_SLEEP="$(command -v sleep)"
REAL_ENV="$(command -v env)"
REAL_GREP="$(command -v grep)"
REAL_SORT="$(command -v sort)"
REAL_TR="$(command -v tr)"
BASE_PATH="$PATH"
unset OLDPWD

# Discover all distinct bash binaries available (bash 3.2 and bash 5.x).
BASH_LIST=()
for cand in /bin/bash /usr/bin/bash /usr/local/bin/bash /opt/homebrew/bin/bash /run/current-system/sw/bin/bash "$(command -v bash 2>/dev/null || true)"; do
    [ -n "$cand" ] && [ -x "$cand" ] || continue
    real_cand="$(cd "$(dirname "$cand")" 2>/dev/null && pwd -P)/$(basename "$cand")"
    already=0
    for existing in ${BASH_LIST[@]+"${BASH_LIST[@]}"}; do
        if [ "$existing" = "$real_cand" ]; then
            already=1
            break
        fi
    done
    if [ "$already" -eq 0 ]; then
        BASH_LIST+=("$real_cand")
        echo "Discovered bash: $real_cand ($("$real_cand" -c 'echo "${BASH_VERSION}"'))"
    fi
done
CURRENT_BASH="${BASH_LIST[0]}"

ROOT_TMP="$(cd "$(mktemp -d)" && pwd -P)"
("$REAL_SLEEP" 300 >/dev/null 2>&1 & echo $! >"$ROOT_TMP/persistent.pid")
PERSISTENT_PID="$(cat "$ROOT_TMP/persistent.pid")"
(trap '' TERM; "$REAL_SLEEP" 300 >/dev/null 2>&1 & echo $! >"$ROOT_TMP/stubborn.pid")
STUBBORN_PID="$(cat "$ROOT_TMP/stubborn.pid")"
cleanup_all() {
    /bin/kill -9 "$PERSISTENT_PID" "$STUBBORN_PID" 2>/dev/null || kill -9 "$PERSISTENT_PID" "$STUBBORN_PID" 2>/dev/null || true
    chflags -R nouchg "$ROOT_TMP" 2>/dev/null || true
    /bin/chmod -R u+w "$ROOT_TMP" 2>/dev/null || true
    rm -rf "$ROOT_TMP"
}
trap cleanup_all EXIT

BASE_STAGE="$ROOT_TMP/base_stage"
STAGE="$ROOT_TMP/stage"
SNAP_SH="$ROOT_TMP/snap_sh"
SNAP_RS="$ROOT_TMP/snap_rs"

export GIT_AUTHOR_NAME="Test Author"
export GIT_AUTHOR_EMAIL="author@example.com"
export GIT_COMMITTER_NAME="Test Committer"
export GIT_COMMITTER_EMAIL="committer@example.com"
export GIT_AUTHOR_DATE="2026-01-15T12:00:00Z"
export GIT_COMMITTER_DATE="2026-01-15T12:00:00Z"
export GIT_CONFIG_NOSYSTEM=1
export USER="testuser"

pass_n=0
fail_n=0
pass() {
    echo "  ✓ $1"
    pass_n=$((pass_n + 1))
}
fail() {
    echo "  ✗ $1" >&2
    fail_n=$((fail_n + 1))
}

hash_file() {
    { md5sum "$1" 2>/dev/null || /sbin/md5 -q "$1" 2>/dev/null || md5 -q "$1" 2>/dev/null || openssl md5 -r "$1"; } | cut -d' ' -f1
}

md5_of_str() {
    printf '%s' "$1" | { md5sum 2>/dev/null || /sbin/md5 -q 2>/dev/null || md5 -q 2>/dev/null || openssl md5 -r; } | cut -d' ' -f1
}

build_base_stage() {
    mkdir -p "$BASE_STAGE/home" "$BASE_STAGE/bin" "$BASE_STAGE/empty"
    touch "$BASE_STAGE/home/.gitconfig"

    # Fake external `kill` on PATH that logs if ever invoked (neither bash builtin kill nor Rust kill(2) may call it).
    cat >"$BASE_STAGE/bin/kill" <<EOF
#!/usr/bin/env bash
printf 'EXTERNAL_KILL_CALLED argv=' >>"$STAGE/tool.log"
printf '<%s>' "\$0" "\$@" >>"$STAGE/tool.log"
printf '\n' >>"$STAGE/tool.log"
echo "external kill called" >"$STAGE/external_kill_called"
exit 1
EOF
    chmod +x "$BASE_STAGE/bin/kill"

    # Wrapper around git that logs every top-level invocation (argv[0], argument boundaries, PWD, and sorted env)
    # when LOG_CALLS=1, and supports failure/signal injection.
    cat >"$BASE_STAGE/bin/git" <<EOF
#!/usr/bin/env bash
if [ "\${LOG_CALLS:-0}" = "1" ] && [ -z "\${_IN_GIT_WRAPPER:-}" ]; then
    {
        printf 'git [PWD=%s] argv=' "\$PWD"
        printf '<%s>' "\$0" "\$@"
        printf ' env={'
        "$REAL_ENV" -0 | "$REAL_GREP" -z -v -E '^(_|SHLVL|__CF_USER_TEXT_ENCODING|_IN_GIT_WRAPPER|BASH_EXECUTION_STRING)=' | LC_ALL=C "$REAL_SORT" -z | "$REAL_TR" '\0' ';'
        printf '}\n'
    } >>"$STAGE/tool.log"
fi
if [ -n "\${FAKE_GIT_PORCELAIN_NONUTF8:-}" ] && [ -z "\${_IN_GIT_WRAPPER:-}" ] && [[ "\$*" == *"worktree list --porcelain"* ]]; then
    printf 'worktree %s/repo\nbranch refs/heads/main\n\nworktree %s/wt/nonutf8-wt\nbranch refs/heads/feat/a\xff\n\n' "$STAGE" "$STAGE"
    exit 0
fi
if [ -n "\${FAKE_GIT_SIGNAL_ON:-}" ] && [ -z "\${_IN_GIT_WRAPPER:-}" ] && [[ "\$*" == *"\${FAKE_GIT_SIGNAL_ON}"* ]]; then
    /bin/kill "-\${FAKE_GIT_SIGNAL_NAME:-INT}" \$\$
fi
if [ -n "\${FAKE_GIT_FAIL_ON:-}" ] && [ -z "\${_IN_GIT_WRAPPER:-}" ] && [[ "\$*" == *"\${FAKE_GIT_FAIL_ON}"* ]]; then
    count_file="$STAGE/git_fail_count"
    n=0
    [ -f "\$count_file" ] && n="\$(cat "\$count_file")"
    n=\$((n + 1))
    echo "\$n" >"\$count_file"
    if [ -z "\${FAKE_GIT_FAIL_WHICH:-}" ] || [[ ",\${FAKE_GIT_FAIL_WHICH}," == *",\${n},"* ]]; then
        echo "fatal: injected git failure for \$*" >&2
        exit 128
    fi
fi
export _IN_GIT_WRAPPER=1
exec "$REAL_GIT" "\$@"
EOF
    chmod +x "$BASE_STAGE/bin/git"

    # Deterministic offline gh fake that logs calls + PWD + env and exits 1.
    cat >"$BASE_STAGE/bin/gh" <<EOF
#!/usr/bin/env bash
if [ "\${LOG_CALLS:-0}" = "1" ]; then
    {
        printf 'gh [PWD=%s] argv=' "\$PWD"
        printf '<%s>' "\$0" "\$@"
        printf ' env={'
        "$REAL_ENV" -0 | "$REAL_GREP" -z -v -E '^(_|SHLVL|__CF_USER_TEXT_ENCODING|_IN_GIT_WRAPPER|BASH_EXECUTION_STRING)=' | LC_ALL=C "$REAL_SORT" -z | "$REAL_TR" '\0' ';'
        printf '}\n'
    } >>"$STAGE/tool.log"
fi
exit 1
EOF
    chmod +x "$BASE_STAGE/bin/gh"

    # Fast sleep wrapper for server shutdown polling loops.
    cat >"$BASE_STAGE/bin/sleep" <<EOF
#!/usr/bin/env bash
if [ "\${FAST_POLL_SLEEP:-0}" = "1" ]; then
    if [ "\${LOG_CALLS:-0}" = "1" ]; then
        {
            printf 'sleep argv='
            printf '<%s>' "\$0" "\$@"
            printf ' env={'
            "$REAL_ENV" -0 | "$REAL_GREP" -z -v -E '^(_|SHLVL|__CF_USER_TEXT_ENCODING|_IN_GIT_WRAPPER|BASH_EXECUTION_STRING)=' | LC_ALL=C "$REAL_SORT" -z | "$REAL_TR" '\0' ';'
            printf '}\n'
        } >>"$STAGE/tool.log"
    fi
    exit 0
fi
exec "$REAL_SLEEP" 0.02
EOF
    chmod +x "$BASE_STAGE/bin/sleep"

    # Landed wrapper that logs env + PWD + argv with boundaries and delegates to real landed.sh.
    cat >"$BASE_STAGE/bin/landed-wrapper.sh" <<EOF
#!/usr/bin/env bash
if [ "\${LOG_CALLS:-0}" = "1" ]; then
    {
        printf 'landed [PWD=%s] argv=' "\$PWD"
        printf '<%s>' "\$0" "\$@"
        printf ' env={'
        "$REAL_ENV" -0 | "$REAL_GREP" -z -v -E '^(_|SHLVL|__CF_USER_TEXT_ENCODING|_IN_GIT_WRAPPER|BASH_EXECUTION_STRING)=' | LC_ALL=C "$REAL_SORT" -z | "$REAL_TR" '\0' ';'
        printf '}\n'
    } >>"$STAGE/tool.log"
fi
exec bash "$REAL_LANDED" "\$@"
EOF
    chmod +x "$BASE_STAGE/bin/landed-wrapper.sh"

    "$REAL_GIT" init -q -b main "$BASE_STAGE/repo"
    "$REAL_GIT" -C "$BASE_STAGE/repo" config user.email "t@t"
    "$REAL_GIT" -C "$BASE_STAGE/repo" config user.name "t"
    printf 'user.bazelrc\n' >"$BASE_STAGE/repo/.gitignore"
    "$REAL_GIT" -C "$BASE_STAGE/repo" add .gitignore
    "$REAL_GIT" -C "$BASE_STAGE/repo" commit -q -m "base"
    "$REAL_GIT" -C "$BASE_STAGE/repo" update-ref refs/remotes/origin/main refs/heads/main
}
build_base_stage

# Build fresh stage at the exact same physical path $STAGE.
init_stage() {
    chflags -R nouchg "$STAGE" 2>/dev/null || true
    /bin/chmod -R u+w "$STAGE" 2>/dev/null || true
    rm -rf "$STAGE"
    cp -R "$BASE_STAGE" "$STAGE"
    ln -sf "$CURRENT_BASH" "$STAGE/bin/bash"
    export HOME="$STAGE/home"
    export GIT_CONFIG_GLOBAL="$STAGE/home/.gitconfig"
    export PATH="$STAGE/bin:$BASE_PATH"
    export WORKTREE_LANDED="$STAGE/bin/landed-wrapper.sh"
    unset OLDPWD
}

norm_stderr() {
    # Narrow normalizer: replace ONLY the leading script/binary path (argv0) with `<worktree>`.
    # Line numbers (`line N:`) and messages must match verbatim.
    sed \
        -e "s|^${SH_BIN}: |<worktree>: |" \
        -e "s|^${RS_BIN}: |<worktree>: |" \
        -e "s|^${STAGE}/standalone/worktree\.sh: |<worktree>: |" \
        -e "s|^${STAGE}/standalone/worktree-rs: |<worktree>: |"
}

capture_snapshot() {
    local out_dir="$1"
    rm -rf "$out_dir"
    mkdir -p "$out_dir"
    cp "$STAGE/stdout" "$out_dir/stdout"
    norm_stderr <"$STAGE/stderr" >"$out_dir/stderr"
    cp "$STAGE/rc" "$out_dir/rc"
    touch "$STAGE/tool.log"
    cp "$STAGE/tool.log" "$out_dir/tool.log"

    if [ -d "$STAGE/repo/.git" ]; then
        "$REAL_GIT" -C "$STAGE/repo" for-each-ref --format='%(refname) %(objectname) %(symref)' >"$out_dir/git_refs"
        "$REAL_GIT" -C "$STAGE/repo" worktree list --porcelain >"$out_dir/git_wt"
        "$REAL_GIT" -C "$STAGE/repo" log --format='%H%x00%an%x00%ae%x00%cn%x00%s' --all >"$out_dir/git_log"
        "$REAL_GIT" -C "$STAGE/repo" status --porcelain >"$out_dir/git_status"
    fi

    (
        cd "$STAGE" || exit 1
        for d in wt repo-worktrees home; do
            [ -d "$d" ] || continue
            find "$d" -mindepth 1 | LC_ALL=C "$REAL_SORT" | while IFS= read -r p; do
                if [ -L "$p" ]; then
                    printf 'L %s -> %s\n' "$p" "$(readlink "$p")"
                elif [ -d "$p" ]; then
                    printf 'D %s\n' "$p"
                elif [ -f "$p" ]; then
                    printf 'F %s %s\n' "$p" "$(hash_file "$p")"
                fi
            done
        done
        if [ -d "repo/.git/worktrees" ]; then
            find "repo/.git/worktrees" -mindepth 1 | LC_ALL=C "$REAL_SORT" | while IFS= read -r p; do
                case "$p" in
                    */index|*/logs|*/logs/*|*/COMMIT_EDITMSG) continue ;;
                esac
                if [ -d "$p" ]; then
                    printf 'D %s\n' "$p"
                elif [ -f "$p" ]; then
                    printf 'F %s %s\n' "$p" "$(hash_file "$p")"
                fi
            done
        fi
    ) >"$out_dir/fs_state"
}

# run_parity <description> <setup_fn> <invoke_fn> [cleanup_fn]
# Runs and compares against EVERY distinct bash in BASH_LIST.
# Sharded under Bazel (shard_count in BUILD): each shard runs every
# TEST_TOTAL_SHARDS-th run_parity scenario, so the suite fits its timeout.
[ -n "${TEST_SHARD_STATUS_FILE:-}" ] && touch "$TEST_SHARD_STATUS_FILE"
PARITY_N=0
run_parity() {
    local desc="$1"
    local setup_fn="$2"
    local invoke_fn="$3"
    local cleanup_fn="${4:-}"
    local mismatch=0
    PARITY_N=$((PARITY_N + 1))
    if [ "$(( (PARITY_N - 1) % ${TEST_TOTAL_SHARDS:-1} ))" != "${TEST_SHARD_INDEX:-0}" ]; then
        return 0
    fi

    for test_bash in "${BASH_LIST[@]}"; do
        CURRENT_BASH="$test_bash"

        # 1. Run bash implementation under $CURRENT_BASH
        init_stage
        "$setup_fn"
        : >"$STAGE/tool.log"
        LOG_CALLS=1 "$invoke_fn" "$CURRENT_BASH" "$SH_BIN" >"$STAGE/stdout" 2>"$STAGE/stderr"
        echo $? >"$STAGE/rc"
        [ -n "$cleanup_fn" ] && "$cleanup_fn"
        capture_snapshot "$SNAP_SH"

        # 2. Run Rust implementation at the exact same path (with $STAGE/bin/bash -> $CURRENT_BASH)
        init_stage
        "$setup_fn"
        : >"$STAGE/tool.log"
        LOG_CALLS=1 "$invoke_fn" "$RS_BIN" >"$STAGE/stdout" 2>"$STAGE/stderr"
        echo $? >"$STAGE/rc"
        [ -n "$cleanup_fn" ] && "$cleanup_fn"
        capture_snapshot "$SNAP_RS"

        # 3. Ensure external kill was never called
        if [ -f "$STAGE/external_kill_called" ]; then
            echo "=== EXTERNAL kill WAS CALLED in [$desc] ($CURRENT_BASH) ===" >&2
            mismatch=1
        fi

        # 4. Compare all captured artifacts
        for f in rc stdout stderr git_refs git_wt git_log git_status fs_state tool.log; do
            if [ -e "$SNAP_SH/$f" ] || [ -e "$SNAP_RS/$f" ]; then
                if ! diff -u "$SNAP_SH/$f" "$SNAP_RS/$f" >"$ROOT_TMP/diff_out" 2>&1; then
                    echo "=== MISMATCH in [$desc] under [$CURRENT_BASH] ($f) ===" >&2
                    cat "$ROOT_TMP/diff_out" >&2
                    mismatch=1
                fi
            fi
        done
    done

    if [ "$mismatch" -eq 0 ]; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

noop_setup() { :; }

invoke_in_repo() {
    BUILD_WORKSPACE_DIRECTORY="$STAGE/repo" WORKTREE_ROOT="$STAGE/wt" "$@"
}

# ── Helper functions for scenarios ───────────────────────────────────────────
make_landed_branch() {
    local br="$1" dir="$2"
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b "$br" "$dir" main
    echo "$br" >"$dir/$(printf '%s' "$br" | "$REAL_TR" '/' '-').txt"
    "$REAL_GIT" -C "$dir" add -A
    "$REAL_GIT" -C "$dir" commit -qm "$br"
    "$REAL_GIT" -C "$STAGE/repo" checkout -q main
    "$REAL_GIT" -C "$STAGE/repo" checkout -q "$br" -- "$(printf '%s' "$br" | "$REAL_TR" '/' '-').txt"
    "$REAL_GIT" -C "$STAGE/repo" commit -qm "$br (#1)"
    "$REAL_GIT" -C "$STAGE/repo" update-ref refs/remotes/origin/main refs/heads/main
}

make_unlanded_branch() {
    local br="$1" dir="$2"
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b "$br" "$dir" main
    echo "wip" >"$dir/wip-$(printf '%s' "$br" | "$REAL_TR" '/' '-').txt"
    "$REAL_GIT" -C "$dir" add -A
    "$REAL_GIT" -C "$dir" commit -qm "wip $br"
}

# ── 1. Help, empty args, and startup checks ──────────────────────────────────
inv_no_args() { invoke_in_repo "$@"; }
run_parity "no args prints usage and exits 0" noop_setup inv_no_args

inv_empty_arg() { invoke_in_repo "$@" ""; }
run_parity "empty first arg prints usage and exits 0" noop_setup inv_empty_arg

inv_h() { invoke_in_repo "$@" -h; }
run_parity "-h prints usage and exits 0" noop_setup inv_h

inv_help() { invoke_in_repo "$@" --help; }
run_parity "--help prints usage and exits 0" noop_setup inv_help

inv_outside_repo() {
    (cd "$STAGE/empty" && unset BUILD_WORKSPACE_DIRECTORY && "$@")
}
run_parity "fails outside git repo when BUILD_WORKSPACE_DIRECTORY is unset" noop_setup inv_outside_repo

inv_bwd_missing() {
    BUILD_WORKSPACE_DIRECTORY="$STAGE/no_such_dir" WORKTREE_ROOT="$STAGE/wt" "$@" --list
}
run_parity "fails with cd error when BUILD_WORKSPACE_DIRECTORY does not exist" noop_setup inv_bwd_missing

setup_bwd_file() {
    echo "not a dir" >"$STAGE/a_file"
}
inv_bwd_file() {
    BUILD_WORKSPACE_DIRECTORY="$STAGE/a_file" WORKTREE_ROOT="$STAGE/wt" "$@" --list
}
run_parity "fails with cd error when BUILD_WORKSPACE_DIRECTORY is a regular file" setup_bwd_file inv_bwd_file

inv_home_unset() {
    (unset HOME && BUILD_WORKSPACE_DIRECTORY="$STAGE/repo" WORKTREE_ROOT="$STAGE/wt" "$@" --list)
}
run_parity "fails with HOME: unbound variable when HOME is unset" noop_setup inv_home_unset

# ── 2. Unknown flags and missing arguments ───────────────────────────────────
inv_unknown_flag() { invoke_in_repo "$@" --not-a-flag; }
run_parity "unknown top-level flag exits 2" noop_setup inv_unknown_flag

inv_unknown_short_flag() { invoke_in_repo "$@" -z; }
run_parity "unknown short flag exits 2" noop_setup inv_unknown_short_flag

inv_unknown_prune_flag() { invoke_in_repo "$@" --prune --bogus; }
run_parity "unknown --prune flag exits 2" noop_setup inv_unknown_prune_flag

inv_unknown_remove_flag() { invoke_in_repo "$@" --remove fix/x --bogus; }
run_parity "unknown --remove flag exits 2" noop_setup inv_unknown_remove_flag

inv_unknown_lock_flag() { invoke_in_repo "$@" --lock --bogus; }
run_parity "unknown --lock flag exits 2" noop_setup inv_unknown_lock_flag

inv_unknown_unlock_flag() { invoke_in_repo "$@" --unlock --bogus; }
run_parity "unknown --unlock flag exits 2" noop_setup inv_unknown_unlock_flag

inv_remove_missing_arg() { invoke_in_repo "$@" --remove; }
run_parity "--remove without branch arg exits 1 with line 613 parameter error" noop_setup inv_remove_missing_arg

inv_remove_empty_arg() { invoke_in_repo "$@" --remove ""; }
run_parity "--remove with empty branch arg exits 1 with line 613 parameter error" noop_setup inv_remove_empty_arg

inv_lock_on_missing() { invoke_in_repo "$@" --lock --on; }
run_parity "--lock --on without arg exits 1 with line 517 parameter error" noop_setup inv_lock_on_missing

inv_lock_on_empty() { invoke_in_repo "$@" --lock --on ""; }
run_parity "--lock --on with empty arg exits 1 with line 517 parameter error" noop_setup inv_lock_on_empty

inv_detach_no_args() { invoke_in_repo "$@" --detach; }
run_parity "--detach without args exits 2 with usage" noop_setup inv_detach_no_args

inv_detach_one_arg() { invoke_in_repo "$@" --detach main; }
run_parity "--detach with one arg exits 2 with usage" noop_setup inv_detach_one_arg

inv_detach_too_many() { invoke_in_repo "$@" --detach main name extra; }
run_parity "--detach with >2 args exits 2 with usage" noop_setup inv_detach_too_many

inv_non_utf8_flag() { invoke_in_repo "$@" $'--bad-\xff\xfe'; }
run_parity "non-UTF-8 unknown flag preserves raw bytes without panicking" noop_setup inv_non_utf8_flag

# ── 3. --list ────────────────────────────────────────────────────────────────
setup_list_multi() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b feat/a "$STAGE/wt/feat-a" main
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q --detach "$STAGE/wt/det" main
    "$REAL_GIT" -C "$STAGE/repo" worktree lock --reason "testing" "$STAGE/wt/feat-a"
}
inv_list() { invoke_in_repo "$@" --list; }
run_parity "--list with multiple worktrees" setup_list_multi inv_list

# ── 4. Create worktree (<branch> [base]) & user.bazelrc variants ─────────────
inv_create_default_base() { invoke_in_repo "$@" feat/new-one; }
run_parity "create worktree with default base (origin/main)" noop_setup inv_create_default_base

setup_no_origin_main() {
    "$REAL_GIT" -C "$STAGE/repo" update-ref -d refs/remotes/origin/main
}
run_parity "create worktree falls back to HEAD when origin/main is absent" setup_no_origin_main inv_create_default_base

setup_explicit_base() {
    "$REAL_GIT" -C "$STAGE/repo" branch custom-base main
}
inv_create_explicit_base() { invoke_in_repo "$@" feat/from-custom custom-base; }
run_parity "create worktree with explicit base ref" setup_explicit_base inv_create_explicit_base

setup_existing_branch() {
    "$REAL_GIT" -C "$STAGE/repo" branch feat/existing main
}
inv_create_existing_branch() { invoke_in_repo "$@" feat/existing; }
run_parity "create worktree reuses existing local branch" setup_existing_branch inv_create_existing_branch

setup_dest_exists() {
    mkdir -p "$STAGE/wt/feat-exists"
}
inv_create_dest_exists() { invoke_in_repo "$@" feat/exists; }
run_parity "create worktree fails when destination already exists" setup_dest_exists inv_create_dest_exists

setup_primary_bazelrc() {
    cat >"$STAGE/repo/user.bazelrc" <<'RC'
# local comment
build --jobs=4
# >>> build cache (managed by tools/remote:setup)
build --remote_cache=grpcs://remote.example.com
build --remote_upload_local_results=false
# <<< build cache (managed by tools/remote:setup)
common:remote --remote_header=x-token=abc
common:remote --bes_header=x-token=def
common:other --remote_header=ignored
RC
}
inv_create_with_bazelrc() { invoke_in_repo "$@" feat/cache-copy; }
run_parity "create worktree propagates primary user.bazelrc cache config" setup_primary_bazelrc inv_create_with_bazelrc

setup_primary_bazelrc_crlf_unclosed_nonutf8() {
    printf '# comment \xff\xfe\r\n# >>> build cache (managed by tools/remote:setup)\r\nbuild --remote_cache=grpcs://crlf.example.com\r\ncommon:remote --remote_header=x-crlf=1\r\n' >"$STAGE/repo/user.bazelrc"
}
run_parity "create worktree propagates primary user.bazelrc with CRLF, missing end marker, and non-UTF-8 bytes" setup_primary_bazelrc_crlf_unclosed_nonutf8 inv_create_with_bazelrc

setup_unreadable_primary_bazelrc() {
    touch "$STAGE/repo/user.bazelrc"
    chmod 0000 "$STAGE/repo/user.bazelrc"
}
cleanup_unreadable_primary_bazelrc() {
    /bin/chmod 0644 "$STAGE/repo/user.bazelrc" 2>/dev/null || true
}
run_parity "create worktree with unreadable primary user.bazelrc prints awk error and exits 2" setup_unreadable_primary_bazelrc inv_create_with_bazelrc cleanup_unreadable_primary_bazelrc

setup_readonly_dest_bazelrc_append() {
    touch "$STAGE/repo/user.bazelrc"
    cat >"$STAGE/bin/mkdir" <<'EOF'
#!/usr/bin/env bash
/bin/mkdir "$@"
if [ -f "$STAGE_DEST_RC" ]; then
    /bin/chmod 0400 "$STAGE_DEST_RC"
fi
EOF
    chmod +x "$STAGE/bin/mkdir"
}
inv_readonly_dest_bazelrc_append() {
    STAGE_DEST_RC="$STAGE/wt/feat-cache-copy/user.bazelrc" invoke_in_repo "$@" feat/cache-copy
}
cleanup_readonly_dest_bazelrc() {
    /bin/chmod -R u+w "$STAGE/wt" 2>/dev/null || true
}
run_parity "setup_tree append redirect failure reports line 558 under both bash 3.2 and bash 5" setup_readonly_dest_bazelrc_append inv_readonly_dest_bazelrc_append cleanup_readonly_dest_bazelrc

setup_wt_root_is_file() {
    echo "blocker" >"$STAGE/wt_file_blocker"
}
inv_create_wt_root_file() {
    BUILD_WORKSPACE_DIRECTORY="$STAGE/repo" WORKTREE_ROOT="$STAGE/wt_file_blocker/sub" "$@" feat/fail-mkdir
}
run_parity "create worktree prints mkdir error and exits 1 when WORKTREE_ROOT cannot be created" setup_wt_root_is_file inv_create_wt_root_file

setup_cache_root_is_file() {
    mkdir -p "$STAGE/home/.cache/bazel"
    echo "blocker" >"$STAGE/home/.cache/bazel/worktrees"
}
run_parity "create worktree prints mkdir error and exits 1 when CACHE_ROOT is a regular file" setup_cache_root_is_file inv_create_default_base

setup_inside_wt() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b feat/inside "$STAGE/wt/inside" main
}
inv_create_from_inside() {
    BUILD_WORKSPACE_DIRECTORY="$STAGE/wt/inside" "$@" feat/from-inside
}
run_parity "create worktree from inside linked worktree places it under <primary>-worktrees" setup_inside_wt inv_create_from_inside

inv_create_unicode() { invoke_in_repo "$@" "feat/日本語/café"; }
run_parity "create worktree with unicode and multi-slash branch name" noop_setup inv_create_unicode

# ── 5. --detach ──────────────────────────────────────────────────────────────
inv_detach_ok() { invoke_in_repo "$@" --detach main review/one; }
run_parity "--detach creates scratch worktree with bazelrc and scratch mark" noop_setup inv_detach_ok

inv_detach_bad_ref() { invoke_in_repo "$@" --detach nonexistent-ref review-bad; }
run_parity "--detach fails on nonexistent commit ref" noop_setup inv_detach_bad_ref

setup_detach_exists() {
    mkdir -p "$STAGE/wt/review-exists"
}
inv_detach_exists() { invoke_in_repo "$@" --detach main review-exists; }
run_parity "--detach fails when destination already exists" setup_detach_exists inv_detach_exists

inv_detach_short_fail() {
    FAKE_GIT_FAIL_ON="rev-parse --short" invoke_in_repo "$@" --detach main review-short-fail
}
run_parity "--detach ignores git rev-parse --short failure inside heredoc and exits 0" noop_setup inv_detach_short_fail

inv_detach_gitdir_fail() {
    FAKE_GIT_FAIL_ON="--git-dir" invoke_in_repo "$@" --detach main review-gd-fail
}
run_parity "--detach with failing git-dir lookup fails redirecting to /vitruvian-scratch at line 647" noop_setup inv_detach_gitdir_fail

# ── 6. --remove ──────────────────────────────────────────────────────────────
setup_rm_basic() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b fix/one "$STAGE/wt/fix-one" main
    mkdir -p "$STAGE/home/.cache/bazel/worktrees/repo-fix-one/sub"
}
inv_rm_basic() { invoke_in_repo "$@" --remove fix/one; }
run_parity "--remove removes worktree and its Bazel cache" setup_rm_basic inv_rm_basic

setup_rm_multi_bazelrc() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b fix/multi "$STAGE/wt/fix-multi" main
    local r1="$STAGE/home/.cache/bazel/worktrees/first-root"
    local r2="$STAGE/home/.cache/bazel/worktrees/second-root"
    mkdir -p "$r1" "$r2"
    printf '# comment \xff\nstartup --output_user_root=%s\nstartup --output_user_root=%s\n' "$r1" "$r2" >"$STAGE/wt/fix-multi/user.bazelrc"
}
inv_rm_multi_bazelrc() { invoke_in_repo "$@" --remove fix/multi; }
run_parity "--remove uses the last startup --output_user_root= line from user.bazelrc (with non-UTF-8 comment)" setup_rm_multi_bazelrc inv_rm_multi_bazelrc

setup_rm_custom_dir() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b fix/two "$STAGE/wt/custom-dir-name" main
}
inv_rm_custom_dir() { invoke_in_repo "$@" --remove fix/two; }
run_parity "--remove finds worktree by branch name regardless of directory name" setup_rm_custom_dir inv_rm_custom_dir

setup_rm_no_wt() {
    "$REAL_GIT" -C "$STAGE/repo" branch fix/no-wt main
}
inv_rm_no_wt() { invoke_in_repo "$@" --remove fix/no-wt; }
run_parity "--remove fails when branch is not checked out in any worktree" setup_rm_no_wt inv_rm_no_wt

inv_rm_primary() { invoke_in_repo "$@" --remove main; }
run_parity "--remove refuses to remove primary checkout" noop_setup inv_rm_primary

inv_rm_self() {
    BUILD_WORKSPACE_DIRECTORY="$STAGE/wt/inside" WORKTREE_ROOT="$STAGE/wt" "$@" --remove feat/inside
}
run_parity "--remove refuses to remove worktree it is running from" setup_inside_wt inv_rm_self

setup_rm_other_from_inside() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b feat/inside "$STAGE/wt/inside" main
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b feat/other "$STAGE/wt/feat-other" main
}
inv_rm_other_from_inside() {
    BUILD_WORKSPACE_DIRECTORY="$STAGE/wt/inside" WORKTREE_ROOT="$STAGE/wt" "$@" --remove feat/other
}
run_parity "--remove from inside a worktree removes another named worktree" setup_rm_other_from_inside inv_rm_other_from_inside

setup_rm_locked() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b fix/locked "$STAGE/wt/fix-locked" main
    "$REAL_GIT" -C "$STAGE/repo" worktree lock --reason "busy working" "$STAGE/wt/fix-locked"
}
inv_rm_locked_force() { invoke_in_repo "$@" --remove fix/locked --force; }
run_parity "--remove refuses locked worktree even with --force" setup_rm_locked inv_rm_locked_force

setup_rm_dirty() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b fix/dirty "$STAGE/wt/fix-dirty" main
    echo "unsaved" >"$STAGE/wt/fix-dirty/notes.txt"
}
inv_rm_dirty_noforce() { invoke_in_repo "$@" --remove fix/dirty; }
run_parity "--remove refuses dirty worktree without --force" setup_rm_dirty inv_rm_dirty_noforce

inv_rm_dirty_force() { invoke_in_repo "$@" --remove fix/dirty --force; }
run_parity "--remove --force removes dirty worktree and warns on stderr" setup_rm_dirty inv_rm_dirty_force

setup_rm_Scratch() {
    LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main scratch-1 >/dev/null 2>&1
}
inv_rm_scratch() { invoke_in_repo "$@" --remove scratch-1; }
run_parity "--remove removes detached scratch worktree by name" setup_rm_Scratch inv_rm_scratch

inv_rm_scratch_delbr() { invoke_in_repo "$@" --remove scratch-1 --delete-branch; }
run_parity "--remove --delete-branch refuses detached scratch worktree" setup_rm_Scratch inv_rm_scratch_delbr

setup_rm_landed() {
    make_landed_branch fix/landed "$STAGE/wt/fix-landed"
}
inv_rm_landed_delbr() { invoke_in_repo "$@" --remove fix/landed --delete-branch; }
run_parity "--remove --delete-branch removes clean landed worktree and branch" setup_rm_landed inv_rm_landed_delbr

setup_rm_landed_interleaved_stderr_first() {
    make_landed_branch fix/landed "$STAGE/wt/fix-landed"
    cat >"$STAGE/bin/custom-landed.sh" <<'EOF'
#!/usr/bin/env bash
printf '\033[31m✗\033[0m stderr-line-first\n' >&2
printf '\033[32m✓\033[0m stdout-line-second\n'
exit 1
EOF
    chmod +x "$STAGE/bin/custom-landed.sh"
    export WORKTREE_LANDED="$STAGE/bin/custom-landed.sh"
}
run_parity "--remove --delete-branch captures landed.sh 2>&1 in interleaved order (stderr first)" setup_rm_landed_interleaved_stderr_first inv_rm_landed_delbr

setup_rm_landed_daemon_grandchild() {
    make_landed_branch fix/landed "$STAGE/wt/fix-landed"
    cat >"$STAGE/bin/daemon-landed.sh" <<EOF
#!/usr/bin/env bash
("$REAL_SLEEP" 300 >/dev/null 2>&1 &)
printf '\033[32m✓\033[0m fix/landed is landed (daemon test)\n'
exit 0
EOF
    chmod +x "$STAGE/bin/daemon-landed.sh"
    export WORKTREE_LANDED="$STAGE/bin/daemon-landed.sh"
}
cleanup_daemon_grandchild() {
    pkill -f "$REAL_SLEEP 300" 2>/dev/null || true
}
run_parity "--remove --delete-branch does not hang when landed.sh spawns a daemonized grandchild (FD_CLOEXEC)" setup_rm_landed_daemon_grandchild inv_rm_landed_delbr

setup_rm_unlanded() {
    make_unlanded_branch fix/unlanded "$STAGE/wt/fix-unlanded"
}
inv_rm_unlanded_delbr() { invoke_in_repo "$@" --remove fix/unlanded --delete-branch; }
run_parity "--remove --delete-branch refuses unlanded branch" setup_rm_unlanded inv_rm_unlanded_delbr

setup_rm_dirty_landed() {
    make_landed_branch fix/dirty-landed "$STAGE/wt/fix-dirty-landed"
    echo "dirty" >"$STAGE/wt/fix-dirty-landed/extra.txt"
}
inv_rm_dirty_landed_delbr_force() { invoke_in_repo "$@" --remove fix/dirty-landed --delete-branch --force; }
run_parity "--remove --delete-branch --force refuses dirty worktree" setup_rm_dirty_landed inv_rm_dirty_landed_delbr_force

setup_rm_default_base() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b fix/defbase "$STAGE/wt/by-hand" main
    local h base
    h="$(md5_of_str "$STAGE/wt/by-hand")"
    base="$STAGE/home/.cache/bazel/_bazel_testuser/$h"
    mkdir -p "$base/external/ro"
    printf '%s' "$STAGE/wt/by-hand" >"$base/DO_NOT_BUILD_HERE"
    chmod -R a-w "$base/external"
    mkdir -p "$STAGE/home/.cache/bazel/_bazel_testuser/otherbase"
}
inv_rm_default_base() { invoke_in_repo "$@" --remove fix/defbase; }
run_parity "--remove prunes default Bazel output base with read-only files" setup_rm_default_base inv_rm_default_base

setup_rm_foreign_base_crlf() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b fix/foreign "$STAGE/wt/not-mine" main
    local h base
    h="$(md5_of_str "$STAGE/wt/not-mine")"
    base="$STAGE/home/.cache/bazel/_bazel_testuser/$h"
    mkdir -p "$base"
    printf '%s\r\nsecond-line\n' "$STAGE/wt/not-mine" >"$base/DO_NOT_BUILD_HERE"
}
inv_rm_foreign_base() { invoke_in_repo "$@" --remove fix/foreign; }
run_parity "--remove preserves CR in DO_NOT_BUILD_HERE (keeps base when CR makes owner differ)" setup_rm_foreign_base_crlf inv_rm_foreign_base

setup_rm_unsafe_bazelrc() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b fix/evil "$STAGE/wt/fix-evil" main
    mkdir -p "$STAGE/home/keep-me"
    printf 'startup --output_user_root=%s/home/keep-me\n' "$STAGE" >"$STAGE/wt/fix-evil/user.bazelrc"
}
inv_rm_unsafe_bazelrc() { invoke_in_repo "$@" --remove fix/evil; }
run_parity "--remove ignores output_user_root outside ~/.cache/bazel/worktrees" setup_rm_unsafe_bazelrc inv_rm_unsafe_bazelrc

setup_rm_servers() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b fix/srv "$STAGE/wt/fix-srv" main
    local root h
    root="$STAGE/home/.cache/bazel/worktrees/repo-fix-srv"
    mkdir -p "$root"
    printf 'startup --output_user_root=%s\n' "$root" >"$STAGE/wt/fix-srv/user.bazelrc"
    h="$(md5_of_str "$STAGE/wt/fix-srv")"
    mkdir -p "$STAGE/home/.cache/bazel/_bazel_testuser/$h/server" "$root/$h/server"
    ("$REAL_SLEEP" 300 >/dev/null 2>&1 & echo $! >"$STAGE/home/.cache/bazel/_bazel_testuser/$h/server/server.pid.txt")
    ("$REAL_SLEEP" 300 >/dev/null 2>&1 & echo $! >"$root/$h/server/server.pid.txt")
}
inv_rm_servers() { invoke_in_repo "$@" --remove fix/srv; }
run_parity "--remove stops Bazel servers in both default and per-worktree roots" setup_rm_servers inv_rm_servers

setup_rm_stubborn_server() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b fix/stubborn "$STAGE/wt/fix-stubborn" main
    local h
    h="$(md5_of_str "$STAGE/wt/fix-stubborn")"
    mkdir -p "$STAGE/home/.cache/bazel/_bazel_testuser/$h/server"
    echo "$STUBBORN_PID" >"$STAGE/home/.cache/bazel/_bazel_testuser/$h/server/server.pid.txt"
}
inv_rm_stubborn_server() {
    FAST_POLL_SLEEP=1 invoke_in_repo "$@" --remove fix/stubborn
}
run_parity "--remove refuses when Bazel server ignores SIGTERM across 20 polls" setup_rm_stubborn_server inv_rm_stubborn_server

setup_rm_no_md5_tool() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b fix/nomd5 "$STAGE/wt/fix-nomd5" main
    cat >"$STAGE/bin/md5sum" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$STAGE/bin/md5sum"
}
inv_rm_no_md5_tool() { invoke_in_repo "$@" --remove fix/nomd5; }
run_parity "--remove refuses when md5 tool produces no digest" setup_rm_no_md5_tool inv_rm_no_md5_tool

setup_rm_md5sum_early_exit() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b fix/md5fallback "$STAGE/wt/fix-md5fallback" main
    cat >"$STAGE/bin/md5sum" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$STAGE/bin/md5sum"
}
inv_rm_md5sum_early_exit() { invoke_in_repo "$@" --remove fix/md5fallback; }
run_parity "--remove falls back to next md5 tool without SIGPIPE when md5sum exits 1 early" setup_rm_md5sum_early_exit inv_rm_md5sum_early_exit

# ── 6b. Pidfile edge cases & NUL bytes in $(...) ─────────────────────────────
setup_pidfile_edge_cases() {
    make_landed_branch p/pid-java "$STAGE/wt/p-pid-java"
    make_landed_branch p/pid-hex "$STAGE/wt/p-pid-hex"
    make_landed_branch p/pid-cr "$STAGE/wt/p-pid-cr"
    make_landed_branch p/pid-vt "$STAGE/wt/p-pid-vt"
    make_landed_branch p/pid-lead-space "$STAGE/wt/p-pid-lead-space"
    make_landed_branch p/pid-trail-tab "$STAGE/wt/p-pid-trail-tab"
    make_landed_branch p/pid-plus "$STAGE/wt/p-pid-plus"
    make_landed_branch p/pid-nul "$STAGE/wt/p-pid-nul"

    local d h pf
    for d in p-pid-java p-pid-hex p-pid-cr p-pid-vt p-pid-lead-space p-pid-trail-tab p-pid-plus p-pid-nul; do
        h="$(md5_of_str "$STAGE/wt/$d")"
        pf="$STAGE/home/.cache/bazel/_bazel_testuser/$h/server/server.pid.txt"
        mkdir -p "$(dirname "$pf")"
        case "$d" in
            p-pid-java) printf 'java\n' >"$pf" ;;
            p-pid-hex) printf '0x1f\n' >"$pf" ;;
            p-pid-cr) printf '%s\r\n' "$PERSISTENT_PID" >"$pf" ;;
            p-pid-vt) printf '%s\v\n' "$PERSISTENT_PID" >"$pf" ;;
            p-pid-lead-space) printf '  \t%s\n' "$PERSISTENT_PID" >"$pf" ;;
            p-pid-trail-tab) printf '%s \t\n' "$PERSISTENT_PID" >"$pf" ;;
            p-pid-plus) printf '+%s\n' "$PERSISTENT_PID" >"$pf" ;;
            p-pid-nul) printf '%s\0%s\n' "${PERSISTENT_PID:0:2}" "${PERSISTENT_PID:2}" >"$pf" ;;
        esac
    done
}
inv_prune_pid_edges() { invoke_in_repo "$@" --prune; }
run_parity "pidfile edge cases (java, 0x1f, trailing CR, VT, leading/trailing space/tab, +pid, NUL) in --prune" setup_pidfile_edge_cases inv_prune_pid_edges

setup_nul_in_files() {
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b fix/nulfiles "$STAGE/wt/fix-nulfiles" main
    local r="$STAGE/home/.cache/bazel/worktrees/repo-fix-nulfiles"
    mkdir -p "$r"
    printf 'startup --output_user_root=%s/home/.cache/bazel/worktrees/repo-\0fix-nulfiles\n' "$STAGE" >"$STAGE/wt/fix-nulfiles/user.bazelrc"
    local h base
    h="$(md5_of_str "$STAGE/wt/fix-nulfiles")"
    base="$STAGE/home/.cache/bazel/_bazel_testuser/$h"
    mkdir -p "$base"
    printf '%s/wt/fix-\0nulfiles\n' "$STAGE" >"$base/DO_NOT_BUILD_HERE"

    LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main s-nul-mark >/dev/null 2>&1
    local gd commit
    gd="$("$REAL_GIT" -C "$STAGE/wt/s-nul-mark" rev-parse --path-format=absolute --git-dir)"
    commit="$("$REAL_GIT" -C "$STAGE/wt/s-nul-mark" rev-parse HEAD)"
    printf '%s\0%s\n' "${commit:0:10}" "${commit:10}" >"$gd/vitruvian-scratch"
    touch -t 202001010000 "$gd/vitruvian-scratch" "$gd/index" "$gd/HEAD" "$gd/logs/HEAD"
}
inv_rm_nul_files() {
    invoke_in_repo "$@" --remove fix/nulfiles && invoke_in_repo "$@" --prune
}
run_parity "NUL bytes in user.bazelrc, DO_NOT_BUILD_HERE, and vitruvian-scratch match bash stripping and warning" setup_nul_in_files inv_rm_nul_files

# ── 7. --lock and --unlock ───────────────────────────────────────────────────
inv_lock_inside_reason() {
    BUILD_WORKSPACE_DIRECTORY="$STAGE/wt/inside" WORKTREE_ROOT="$STAGE/wt" "$@" --lock agent wren reviewing PR
}
run_parity "--lock from inside worktree with custom reason" setup_inside_wt inv_lock_inside_reason

inv_lock_on_default_reason() {
    while [ "$(date +%S)" = "59" ]; do "$REAL_SLEEP" 0.2; done
    invoke_in_repo "$@" --lock --on feat/inside
}
run_parity "--lock --on branch with default timestamped reason" setup_inside_wt inv_lock_on_default_reason

inv_lock_already_locked() {
    invoke_in_repo "$@" --lock --on fix/locked
}
run_parity "--lock on already locked worktree succeeds and says so" setup_rm_locked inv_lock_already_locked

inv_unlock_locked() {
    invoke_in_repo "$@" --unlock --on fix/locked
}
run_parity "--unlock --on unlocks a locked worktree" setup_rm_locked inv_unlock_locked

inv_unlock_already_unlocked() {
    invoke_in_repo "$@" --unlock --on feat/inside
}
run_parity "--unlock on unlocked worktree succeeds and says so" setup_inside_wt inv_unlock_already_unlocked

inv_lock_primary() { invoke_in_repo "$@" --lock; }
run_parity "--lock on primary checkout is refused" noop_setup inv_lock_primary

inv_unlock_primary() { invoke_in_repo "$@" --unlock; }
run_parity "--unlock on primary checkout is refused" noop_setup inv_unlock_primary

inv_lock_nonexistent() { invoke_in_repo "$@" --lock --on no/such/branch; }
run_parity "--lock --on nonexistent branch is refused" noop_setup inv_lock_nonexistent

# ── 8. --prune (dry run, --execute, inside worktree, missing dir, TTLs, unborn HEAD) ──
age_scratch_tree() {
    local gd
    gd="$("$REAL_GIT" -C "$1" rev-parse --path-format=absolute --git-dir)"
    touch -t 202001010000 "$gd/vitruvian-scratch" "$gd/index" "$gd/HEAD" "$gd/logs/HEAD"
}

setup_prune_comprehensive() {
    # Worktree cases:
    make_landed_branch p/landed "$STAGE/wt/p-landed"
    make_unlanded_branch p/unlanded "$STAGE/wt/p-unlanded"
    make_landed_branch p/dirty "$STAGE/wt/p-dirty"
    echo "dirty" >"$STAGE/wt/p-dirty/untracked.txt"
    make_landed_branch p/locked "$STAGE/wt/p-locked"
    "$REAL_GIT" -C "$STAGE/repo" worktree lock --reason "agent at work" "$STAGE/wt/p-locked"
    make_landed_branch p/busy "$STAGE/wt/p-busy"
    local h
    h="$(md5_of_str "$STAGE/wt/p-busy")"
    local pid_file="$STAGE/home/.cache/bazel/_bazel_testuser/$h/server/server.pid.txt"
    mkdir -p "$(dirname "$pid_file")"
    echo "$PERSISTENT_PID" >"$pid_file"
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b p/new "$STAGE/wt/p-new" main
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q --detach "$STAGE/wt/p-detached" main
    make_landed_branch p/missing "$STAGE/wt/p-missing"
    rm -rf "$STAGE/wt/p-missing"

    # Scratch tree cases:
    LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main s-old >/dev/null 2>&1
    LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main s-young >/dev/null 2>&1
    LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main s-dirty >/dev/null 2>&1
    LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main s-locked >/dev/null 2>&1
    LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main s-used >/dev/null 2>&1
    LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main s-moved >/dev/null 2>&1
    LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main s-mb-moved >/dev/null 2>&1
    LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main s-unborn >/dev/null 2>&1
    "$REAL_GIT" -C "$STAGE/repo" commit --allow-empty -qm "second commit"
    "$REAL_GIT" -C "$STAGE/repo" update-ref refs/remotes/origin/main refs/heads/main
    "$REAL_GIT" -C "$STAGE/wt/s-moved" checkout -q --detach main
    printf 'a日本語日本語日本語日本語extra\n' >"$("$REAL_GIT" -C "$STAGE/wt/s-mb-moved" rev-parse --path-format=absolute --git-dir)/vitruvian-scratch"
    # Unborn HEAD in scratch worktree (`git rev-parse HEAD` outputs `HEAD` and exits 128):
    printf 'ref: refs/heads/unborn-branch\n' >"$("$REAL_GIT" -C "$STAGE/wt/s-unborn" rev-parse --path-format=absolute --git-dir)/HEAD"
    for d in s-old s-dirty s-locked s-used s-moved s-mb-moved s-unborn; do age_scratch_tree "$STAGE/wt/$d"; done
    touch "$("$REAL_GIT" -C "$STAGE/wt/s-used" rev-parse --path-format=absolute --git-dir)/index"
    echo "wip" >"$STAGE/wt/s-dirty/notes.txt"
    "$REAL_GIT" -C "$STAGE/repo" worktree lock --reason "reviewing" "$STAGE/wt/s-locked"

    # Branches with no worktree:
    make_landed_branch b/landed "$STAGE/wt/b-landed"
    "$REAL_GIT" -C "$STAGE/repo" worktree remove "$STAGE/wt/b-landed"
    make_unlanded_branch b/unlanded "$STAGE/wt/b-unlanded"
    "$REAL_GIT" -C "$STAGE/repo" worktree remove "$STAGE/wt/b-unlanded"
    make_landed_branch b/grew "$STAGE/wt/b-grew"
    echo "more" >"$STAGE/wt/b-grew/more.txt"
    "$REAL_GIT" -C "$STAGE/wt/b-grew" add -A
    "$REAL_GIT" -C "$STAGE/wt/b-grew" commit -qm "extra commit"
    "$REAL_GIT" -C "$STAGE/repo" worktree remove "$STAGE/wt/b-grew"
    "$REAL_GIT" -C "$STAGE/repo" branch -q b/empty main
}

inv_prune_dry() { invoke_in_repo "$@" --prune; }
run_parity "--prune dry-run across all worktree, scratch, unborn-HEAD, missing-dir, and branch states" setup_prune_comprehensive inv_prune_dry

inv_prune_exec() { invoke_in_repo "$@" --prune --execute; }
run_parity "--prune --execute across all worktree, scratch, unborn-HEAD, missing-dir, and branch states" setup_prune_comprehensive inv_prune_exec

inv_prune_from_inside() {
    BUILD_WORKSPACE_DIRECTORY="$STAGE/wt/p-landed" WORKTREE_ROOT="$STAGE/wt" "$@" --prune
}
run_parity "--prune run from inside a linked worktree keeps that worktree" setup_prune_comprehensive inv_prune_from_inside

setup_scratch_ttl_edge() {
    LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main s-octal >/dev/null 2>&1
    local gd
    gd="$("$REAL_GIT" -C "$STAGE/wt/s-octal" rev-parse --path-format=absolute --git-dir)"
    # Touch to 2 hours ago: with octal 010 (=8h) it is kept; with 1h it is removed.
    python3 -c '
import os, sys, time
t = time.time() - 7200
for p in sys.argv[1:]:
    os.utime(p, (t, t))
' "$gd/vitruvian-scratch" "$gd/index" "$gd/HEAD" "$gd/logs/HEAD"
}
inv_prune_ttl_octal() {
    WORKTREE_SCRATCH_TTL_HOURS="010" invoke_in_repo "$@" --prune
}
run_parity "--prune treats 010 WORKTREE_SCRATCH_TTL_HOURS as octal 8 hours" setup_scratch_ttl_edge inv_prune_ttl_octal

inv_prune_ttl_1h() {
    WORKTREE_SCRATCH_TTL_HOURS="1" invoke_in_repo "$@" --prune
}
run_parity "--prune with WORKTREE_SCRATCH_TTL_HOURS=1 removes 2-hour-old scratch tree" setup_scratch_ttl_edge inv_prune_ttl_1h

# ── 9. Failure & signal injection on external tools & filesystem ─────────────
inv_rm_git_fail() {
    FAKE_GIT_FAIL_ON="worktree remove" invoke_in_repo "$@" --remove fix/one
}
run_parity "failure injection: git worktree remove failing returns error" setup_rm_basic inv_rm_git_fail

inv_git_killed_by_sigint() {
    FAKE_GIT_SIGNAL_ON="worktree list" FAKE_GIT_SIGNAL_NAME="INT" invoke_in_repo "$@" --list
}
run_parity "signal injection: foreground child git killed by SIGINT exits 130 (128+2)" noop_setup inv_git_killed_by_sigint

setup_tr_killed_by_sigterm() {
    cat >"$STAGE/bin/tr" <<'EOF'
#!/usr/bin/env bash
/bin/kill -TERM $$
EOF
    chmod +x "$STAGE/bin/tr"
}
inv_tr_killed_by_sigterm() {
    invoke_in_repo "$@" feat/sigterm-tr
}
run_parity "signal injection: child tr in command substitution killed by SIGTERM exits 143 (128+15)" setup_tr_killed_by_sigterm inv_tr_killed_by_sigterm

setup_git_not_executable() {
    chmod -x "$STAGE/bin/git"
}
inv_git_not_executable() {
    PATH="$STAGE/bin" invoke_in_repo "$@" --list
}
run_parity "failure injection: non-executable git on PATH exits 126 with Permission denied" setup_git_not_executable inv_git_not_executable

inv_git_not_found() {
    PATH="$STAGE/empty" invoke_in_repo "$@" --list
}
run_parity "failure injection: missing git on PATH exits 127 with command not found" noop_setup inv_git_not_found

inv_rm_missing_landed() {
    WORKTREE_LANDED="/nonexistent/landed.sh" invoke_in_repo "$@" --remove fix/landed --delete-branch
}
run_parity "failure injection: missing WORKTREE_LANDED refuses branch deletion" setup_rm_landed inv_rm_missing_landed

setup_real_no_landed() {
    make_landed_branch fix/landed "$STAGE/wt/fix-landed"
    mkdir -p "$STAGE/standalone"
    cp "$SH_BIN" "$STAGE/standalone/worktree.sh"
    cp "$RS_BIN" "$STAGE/standalone/worktree-rs"
    chmod +x "$STAGE/standalone/worktree.sh" "$STAGE/standalone/worktree-rs"
}
inv_real_no_landed() {
    if [ $# -eq 2 ]; then
        (cd "$STAGE/empty" && unset WORKTREE_LANDED RUNFILES_DIR RUNFILES_MANIFEST_FILE TEST_SRCDIR && BUILD_WORKSPACE_DIRECTORY="$STAGE/repo" WORKTREE_ROOT="$STAGE/wt" "$1" "$STAGE/standalone/worktree.sh" --remove fix/landed --delete-branch)
    else
        (cd "$STAGE/empty" && unset WORKTREE_LANDED RUNFILES_DIR RUNFILES_MANIFEST_FILE TEST_SRCDIR && BUILD_WORKSPACE_DIRECTORY="$STAGE/repo" WORKTREE_ROOT="$STAGE/wt" "$STAGE/standalone/worktree-rs" --remove fix/landed --delete-branch)
    fi
}
run_parity "real cannot-find-landed.sh outside runfiles with env vars unset" setup_real_no_landed inv_real_no_landed

inv_fail_wt_list_all_rm() {
    FAKE_GIT_FAIL_ON="worktree list" invoke_in_repo "$@" --remove fix/one
}
run_parity "failure injection: git worktree list failing on all calls in --remove" setup_rm_basic inv_fail_wt_list_all_rm

inv_fail_wt_list_first_rm() {
    FAKE_GIT_FAIL_ON="worktree list" FAKE_GIT_FAIL_WHICH="1" invoke_in_repo "$@" --remove fix/one
}
run_parity "failure injection: git worktree list failing on 1st call in find_worktree prints no worktree" setup_rm_basic inv_fail_wt_list_first_rm

inv_fail_wt_list_prune() {
    FAKE_GIT_FAIL_ON="worktree list" invoke_in_repo "$@" --prune
}
run_parity "failure injection: git worktree list failing in --prune" setup_rm_basic inv_fail_wt_list_prune

inv_fail_wt_list_prune_exec_recheck() {
    FAKE_GIT_FAIL_ON="worktree list" FAKE_GIT_FAIL_WHICH="3,4" invoke_in_repo "$@" --prune --execute
}
run_parity "failure injection: git worktree list failing inside remove_one during --prune --execute continues" setup_rm_landed inv_fail_wt_list_prune_exec_recheck

inv_fail_for_each_ref_prune() {
    FAKE_GIT_FAIL_ON="for-each-ref" invoke_in_repo "$@" --prune
}
run_parity "failure injection: git for-each-ref failing in --prune is ignored like process substitution" setup_prune_comprehensive inv_fail_for_each_ref_prune

inv_fail_wt_lock() {
    FAKE_GIT_FAIL_ON="worktree lock" invoke_in_repo "$@" --lock --on feat/inside
}
run_parity "failure injection: git worktree lock failing returns git exit code" setup_inside_wt inv_fail_wt_lock

setup_branch_d_lockfile() {
    make_landed_branch fix/first "$STAGE/wt/fix-first"
    make_landed_branch fix/second "$STAGE/wt/fix-second"
    mkdir -p "$STAGE/repo/.git/refs/heads/fix"
    touch "$STAGE/repo/.git/refs/heads/fix/first.lock"
}
inv_rm_branch_d_lockfile() {
    invoke_in_repo "$@" --remove fix/first --delete-branch
}
run_parity "failure injection: git branch -D lockfile in --remove --delete-branch aborts before printing removed" setup_branch_d_lockfile inv_rm_branch_d_lockfile

inv_prune_exec_branch_d_lockfile() {
    invoke_in_repo "$@" --prune --execute
}
run_parity "failure injection: git branch -D lockfile in --prune --execute prints removed and continues to second worktree" setup_branch_d_lockfile inv_prune_exec_branch_d_lockfile

make_undeletable_file() {
    local f="$1"
    mkdir -p "$(dirname "$f")"
    echo "undeletable" >"$f"
    if ! chflags uchg "$f" 2>/dev/null; then
        chmod 0500 "$(dirname "$f")"
    fi
}
cleanup_undeletable() {
    chflags -R nouchg "$STAGE" 2>/dev/null || true
    /bin/chmod -R u+w "$STAGE" 2>/dev/null || true
}
setup_rm_undeletable_cache() {
    make_landed_branch fix/undel "$STAGE/wt/fix-undel"
    make_landed_branch fix/second "$STAGE/wt/fix-second"
    make_undeletable_file "$STAGE/home/.cache/bazel/worktrees/repo-fix-undel/sub/stuck"
}
inv_rm_undeletable() {
    invoke_in_repo "$@" --remove fix/undel --delete-branch
}
run_parity "failure injection: undeletable file in output_root stops --remove with exit 1 and keeps branch" setup_rm_undeletable_cache inv_rm_undeletable cleanup_undeletable

inv_prune_exec_undeletable() {
    invoke_in_repo "$@" --prune --execute
}
run_parity "failure injection: undeletable file in output_root during --prune --execute prints error and continues" setup_rm_undeletable_cache inv_prune_exec_undeletable cleanup_undeletable

# ── 10. Closed stdout (>&-), /dev/full, and SIGPIPE (default & ignored) ──────
inv_closed_stdout_prune_exec() {
    invoke_in_repo "$@" --prune --execute >&-
}
run_parity "closed stdout (>&-): --prune --execute exits 1 at line 398 before deleting anything" setup_prune_comprehensive inv_closed_stdout_prune_exec

setup_rm_landed_with_caches() {
    make_landed_branch fix/landed "$STAGE/wt/fix-landed"
    mkdir -p "$STAGE/home/.cache/bazel/worktrees/repo-fix-landed/sub"
    local h
    h="$(md5_of_str "$STAGE/wt/fix-landed")"
    mkdir -p "$STAGE/home/.cache/bazel/_bazel_testuser/$h/sub"
}
inv_closed_stdout_rm_delbr() {
    invoke_in_repo "$@" --remove fix/landed --delete-branch >&-
}
run_parity "closed stdout (>&-): --remove --delete-branch stops at line 357 before deleting default base or branch" setup_rm_landed_with_caches inv_closed_stdout_rm_delbr

inv_closed_stdout_rm_delbr_no_cache() {
    invoke_in_repo "$@" --remove fix/landed --delete-branch >&-
}
run_parity "closed stdout (>&-): --remove --delete-branch without caches stops at line 366" setup_rm_landed inv_closed_stdout_rm_delbr_no_cache

inv_closed_stdout_lock() {
    invoke_in_repo "$@" --lock --on feat/inside reason >&-
}
run_parity "closed stdout (>&-): --lock stops at line 543 write error" setup_inside_wt inv_closed_stdout_lock

if [ -w /dev/full ]; then
    inv_dev_full_prune_exec() {
        invoke_in_repo "$@" --prune --execute >/dev/full
    }
    run_parity "/dev/full: --prune --execute exits 1 at line 398 before deleting anything" setup_prune_comprehensive inv_dev_full_prune_exec

    inv_dev_full_rm_delbr() {
        invoke_in_repo "$@" --remove fix/landed --delete-branch >/dev/full
    }
    run_parity "/dev/full: --remove --delete-branch stops at line 357 before deleting default base or branch" setup_rm_landed_with_caches inv_dev_full_rm_delbr
else
    echo "  (skipped /dev/full scenarios: /dev/full not available on macOS)"
fi

inv_sigpipe_help() {
    invoke_in_repo "$@" --help | head -n 1
}
run_parity "SIGPIPE (default): --help piped to head -n 1 exits cleanly without panic" noop_setup inv_sigpipe_help

inv_sigpipe_prune() {
    invoke_in_repo "$@" --prune | head -n 2
}
run_parity "SIGPIPE (default): --prune piped to head -n 2 terminates via SIGPIPE without panic" setup_prune_comprehensive inv_sigpipe_prune

inv_sigpipe_ign_prune_exec() {
    (trap '' PIPE; invoke_in_repo "$@" --prune --execute | head -n 1)
}
run_parity "SIGPIPE ignored (trap '' PIPE): --prune --execute | head -n 1 hits EPIPE write error at line 428 before deleting anything" setup_prune_comprehensive inv_sigpipe_ign_prune_exec

# ── 11. Locale collation & non-UTF-8 branch names (LC_ALL=en_US.UTF-8) ───────
if locale -a 2>/dev/null | "$REAL_GREP" -x "en_US.UTF-8" >/dev/null; then
    setup_locale_branches() {
        for b in A0 A_0 AB A_B AC; do
            make_landed_branch "$b" "$STAGE/wt/$b"
            "$REAL_GIT" -C "$STAGE/repo" worktree remove "$STAGE/wt/$b"
        done
        for w in x x_y a-b A-c a_b; do
            make_landed_branch "wt/$w" "$STAGE/wt/$w"
        done
        LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main s-mb-utf8 >/dev/null 2>&1
        printf 'a日本語日本語日本語日本語extra\n' >"$("$REAL_GIT" -C "$STAGE/wt/s-mb-utf8" rev-parse --path-format=absolute --git-dir)/vitruvian-scratch"
        age_scratch_tree "$STAGE/wt/s-mb-utf8"
    }
    inv_locale_prune() {
        LC_ALL=en_US.UTF-8 invoke_in_repo "$@" --prune
    }
    run_parity "locale collation: --prune under LC_ALL=en_US.UTF-8 with C-vs-UTF8 order names" setup_locale_branches inv_locale_prune

    inv_non_utf8_create() {
        LC_ALL=en_US.UTF-8 invoke_in_repo "$@" $'feat/bad-\xff\xfe'
    }
    run_parity "non-UTF-8 branch creation under LC_ALL=en_US.UTF-8 aborts in tr with Illegal byte sequence" noop_setup inv_non_utf8_create

    inv_non_utf8_detach() {
        LC_ALL=en_US.UTF-8 invoke_in_repo "$@" --detach main $'bad-\xff\xfe'
    }
    run_parity "non-UTF-8 --detach name under LC_ALL=en_US.UTF-8 aborts in tr with Illegal byte sequence" noop_setup inv_non_utf8_detach
else
    echo "  (skipped LC_ALL=en_US.UTF-8 scenarios: locale not installed)"
fi

# ── 12. KEEP-SAFE deliberate divergences ─────────────────────────────────────
# 12a. Numeric-looking branch names: in bash, awk `$2 == b` matches branch `1.10`
# when asked for `1.1` and deletes the wrong worktree; Rust keeps `1.10` safe.
init_stage
"$REAL_GIT" -C "$STAGE/repo" worktree add -q -b "1.10" "$STAGE/wt/br-1-10" main
invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --remove "1.1" >"$ROOT_TMP/sh_out" 2>"$ROOT_TMP/sh_err"
sh_rc=$?
sh_exists=0
[ -d "$STAGE/wt/br-1-10" ] && sh_exists=1

init_stage
"$REAL_GIT" -C "$STAGE/repo" worktree add -q -b "1.10" "$STAGE/wt/br-1-10" main
invoke_in_repo "$RS_BIN" --remove "1.1" >"$ROOT_TMP/rs_out" 2>"$ROOT_TMP/rs_err"
rs_rc=$?
rs_exists=0
[ -d "$STAGE/wt/br-1-10" ] && rs_exists=1

if [ "$sh_rc" -eq 0 ] && [ "$sh_exists" -eq 0 ] && [ "$rs_rc" -eq 1 ] && [ "$rs_exists" -eq 1 ] && "$REAL_GREP" -q "no worktree has branch 1.1 checked out" "$ROOT_TMP/rs_err"; then
    pass "KEEP-SAFE divergence: --remove 1.1 does not delete worktree on branch 1.10 in Rust"
else
    fail "KEEP-SAFE divergence check for numeric branch 1.1 vs 1.10 failed (sh_rc=$sh_rc sh_exists=$sh_exists rs_rc=$rs_rc rs_exists=$rs_exists)"
fi

# 12b. Non-decimal WORKTREE_SCRATCH_TTL_HOURS: in bash, arithmetic failure on `08`
# leaves `recent` empty and marks the young scratch tree as REMOVE; Rust emits the
# identical stderr arithmetic error (`line 246: 08: value too great for base`) but
# keeps the scratch tree safe.
init_stage
LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main s-ttl-safe >/dev/null 2>&1
WORKTREE_SCRATCH_TTL_HOURS="08" invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --prune >"$ROOT_TMP/sh_ttl_out" 2>"$ROOT_TMP/sh_ttl_err"
norm_stderr <"$ROOT_TMP/sh_ttl_err" >"$ROOT_TMP/sh_ttl_err_norm"

init_stage
LOG_CALLS=0 invoke_in_repo "$CURRENT_BASH" "$SH_BIN" --detach main s-ttl-safe >/dev/null 2>&1
WORKTREE_SCRATCH_TTL_HOURS="08" invoke_in_repo "$RS_BIN" --prune >"$ROOT_TMP/rs_ttl_out" 2>"$ROOT_TMP/rs_ttl_err"
norm_stderr <"$ROOT_TMP/rs_ttl_err" >"$ROOT_TMP/rs_ttl_err_norm"

if diff -u "$ROOT_TMP/sh_ttl_err_norm" "$ROOT_TMP/rs_ttl_err_norm" >/dev/null 2>&1 &&
   "$REAL_GREP" -q "REMOVE  .*/wt/s-ttl-safe" "$ROOT_TMP/sh_ttl_out" &&
   "$REAL_GREP" -q "KEEP    .*/wt/s-ttl-safe" "$ROOT_TMP/rs_ttl_out"; then
    pass "KEEP-SAFE divergence: invalid WORKTREE_SCRATCH_TTL_HOURS=08 prints identical stderr error and keeps scratch tree in Rust"
else
    diff -u "$ROOT_TMP/sh_ttl_err_norm" "$ROOT_TMP/rs_ttl_err_norm" >&2 || true
    fail "KEEP-SAFE divergence check for WORKTREE_SCRATCH_TTL_HOURS=08 failed"
fi

# 12c. Non-UTF-8 branch name in output_root_of during --remove: on macOS in
# UTF-8 locale, `tr '/' '-'` truncates `feat/a<invalid>` to `feat-a` and `rm -rf`s
# sibling cache root `repo-feat-a`; Rust uses pure-byte slugging in `output_root_of`
# so `repo-feat-a` is never deleted.
if locale -a 2>/dev/null | "$REAL_GREP" -x "en_US.UTF-8" >/dev/null; then
    init_stage
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b feat/a-holder "$STAGE/wt/nonutf8-wt" main
    mkdir -p "$STAGE/home/.cache/bazel/worktrees/repo-feat-a"
    FAKE_GIT_PORCELAIN_NONUTF8=1 LC_ALL=en_US.UTF-8 invoke_in_repo "$RS_BIN" --remove $'feat/a\xff' >/dev/null 2>&1
    rs_rc=$?
    if [ "$rs_rc" -eq 0 ] && [ -d "$STAGE/home/.cache/bazel/worktrees/repo-feat-a" ] && [ ! -d "$STAGE/wt/nonutf8-wt" ]; then
        pass "KEEP-SAFE divergence: output_root_of with non-UTF-8 branch never deletes truncated sibling cache root repo-feat-a"
    else
        fail "KEEP-SAFE divergence check for non-UTF-8 output_root_of failed (rs_rc=$rs_rc)"
    fi
fi

echo "worktree-rs-parity_test: $pass_n passed, $fail_n failed"
[ "$fail_n" -eq 0 ]
