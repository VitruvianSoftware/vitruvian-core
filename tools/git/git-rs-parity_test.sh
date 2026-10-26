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

# git-rs-parity_test.sh — side-by-side behavioural parity test comparing git.sh and
# the Rust port across all workflows, edge cases, and failure injections.
set -uo pipefail

SH_BIN="${1:?usage: git-rs-parity_test.sh <git.sh> <git-rs>}"
RS_BIN="${2:?usage: git-rs-parity_test.sh <git.sh> <git-rs>}"
SH_BIN="$(cd "$(dirname "$SH_BIN")" && pwd)/$(basename "$SH_BIN")"
RS_BIN="$(cd "$(dirname "$RS_BIN")" && pwd)/$(basename "$RS_BIN")"
REAL_GIT="$(command -v git)"

# Discover every distinct bash binary available on the system (e.g. bash 3.2 and bash 5.2).
BASH_BINS=()
BASH_REALPATHS="|"
for cand in /bin/bash /usr/bin/bash /usr/local/bin/bash /opt/homebrew/bin/bash /run/current-system/sw/bin/bash "$(command -v bash 2>/dev/null || true)"; do
    [ -n "$cand" ] && [ -x "$cand" ] || continue
    rp="$(cd "$(dirname "$cand")" 2>/dev/null && pwd -P)/$(basename "$cand")"
    case "$BASH_REALPATHS" in
        *"|$rp|"*) ;;
        *)
            BASH_REALPATHS="${BASH_REALPATHS}${rp}|"
            BASH_BINS+=("$cand")
            ;;
    esac
done
if [ "${#BASH_BINS[@]}" -eq 0 ]; then
    BASH_BINS=(bash)
fi
TEST_BASH="${BASH_BINS[0]}"

find_real_runfiles_bash() {
    local f="bazel_tools/tools/bash/runfiles/runfiles.bash"
    if [ -f "${RUNFILES_DIR:-/dev/null}/$f" ]; then
        printf '%s\n' "${RUNFILES_DIR}/$f"
        return 0
    fi
    if [ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]; then
        local target
        target="$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE}" | cut -f2- -d' ')"
        if [ -n "$target" ] && [ -f "$target" ]; then
            printf '%s\n' "$target"
            return 0
        fi
    fi
    if [ -f "$0.runfiles/$f" ]; then
        printf '%s\n' "$0.runfiles/$f"
        return 0
    fi
    if [ -f "$0.runfiles_manifest" ]; then
        local target
        target="$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')"
        if [ -n "$target" ] && [ -f "$target" ]; then
            printf '%s\n' "$target"
            return 0
        fi
    fi
    return 1
}
REAL_RUNFILES_BASH="$(find_real_runfiles_bash || true)"

root_tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$root_tmp"' EXIT

build_dump_argv_env() {
    local bin="$root_tmp/dump-argv-env"
    cat >"$bin" <<'PERLEOF'
#!/usr/bin/perl
$prefix = shift @ARGV;
$out = "$prefix ";
for $a (@ARGV) {
    $out .= "<$a>";
}
%ignore = (
    "SHLVL" => 1,
    "_" => 1,
    "BASH_EXECUTION_STRING" => 1,
    "SHELLOPTS" => 1,
    "CURRENT_KIND" => 1,
    "SNAP_DIR" => 1,
    "TEST_BASH" => 1,
    "ACTIVE_BIN" => 1,
    "RUNFILES_REPO_MAPPING" => 1,
    "__CFBundleIdentifier" => 1,
    "OLDPWD" => 1,
);
@items = ();
for $k (sort keys %ENV) {
    next if $ignore{$k} || $k =~ /^(?:BASH_FUNC_|_RLOCATION_)/;
    $entry = "$k=$ENV{$k}";
    $entry =~ s/\n/\\n/g;
    push @items, $entry;
}
$out .= " | ENV=" . join("|", @items) . "\n";
syswrite(STDOUT, $out);
PERLEOF
    chmod +x "$bin"
}
build_dump_argv_env

pass_n=0
fail_n=0
pass() { echo "  ✓ $1"; pass_n=$((pass_n + 1)); }
fail() { echo "  ✗ $1" >&2; fail_n=$((fail_n + 1)); }

SECRET="Zq8Lm3Rt""7Vx2Kp9W""n4Hs6Jd1""Fg5Bc0Ya"
plant_secret() { printf 'first line\napi_token = "%s"\n' "$SECRET" >"$1"; }

# Replace ONLY the script/binary path prefix on stderr (`$SH_BIN:` or `$RS_BIN:`),
# never touching `: line <N>:` or anything after it.
normalize_stderr() {
    local err_f="$1"
    local active_bin="$RS_BIN"
    if [ "$CURRENT_KIND" = "sh" ]; then
        active_bin="${ACTIVE_BIN:-$SH_BIN}"
    else
        active_bin="${ACTIVE_BIN:-$RS_BIN}"
    fi
    LC_ALL=C sed "s|^${active_bin}:|<PROG>:|" "$err_f"
}

# Invoke the current subject ("sh" or "rs") and log exact stdout, stderr, and exit code.
step() {
    local label="$1" wt="$2"; shift 2
    local out_f="$STAGE/.step.out" err_f="$STAGE/.step.err" rc=0
    if [ "$CURRENT_KIND" = "sh" ]; then
        (cd "$STAGE" && unset OLDPWD && BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="${WDIR:-$wt}" "$TEST_BASH" "${ACTIVE_BIN:-$SH_BIN}" "$@") >"$out_f" 2>"$err_f" || rc=$?
    else
        (cd "$STAGE" && unset OLDPWD && BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="${WDIR:-$wt}" "${ACTIVE_BIN:-$RS_BIN}" "$@") >"$out_f" 2>"$err_f" || rc=$?
    fi
    {
        printf '=== STEP: %s (rc=%d) ===\n' "$label" "$rc"
        printf -- '--- stdout ---\n'
        cat "$out_f"
        printf -- '--- stderr ---\n'
        normalize_stderr "$err_f"
        printf '\n'
    } >>"$SNAP_DIR/steps.log"
    rm -f "$out_f" "$err_f"
}

step_no_bwd() {
    local label="$1" run_dir="$2"; shift 2
    local out_f="$STAGE/.step.out" err_f="$STAGE/.step.err" rc=0
    if [ "$CURRENT_KIND" = "sh" ]; then
        (cd "$run_dir" && unset OLDPWD BUILD_WORKSPACE_DIRECTORY BUILD_WORKING_DIRECTORY && "$TEST_BASH" "${ACTIVE_BIN:-$SH_BIN}" "$@") >"$out_f" 2>"$err_f" || rc=$?
    else
        (cd "$run_dir" && unset OLDPWD BUILD_WORKSPACE_DIRECTORY BUILD_WORKING_DIRECTORY && "${ACTIVE_BIN:-$RS_BIN}" "$@") >"$out_f" 2>"$err_f" || rc=$?
    fi
    {
        printf '=== STEP: %s (rc=%d) ===\n' "$label" "$rc"
        printf -- '--- stdout ---\n'
        cat "$out_f"
        printf -- '--- stderr ---\n'
        normalize_stderr "$err_f"
        printf '\n'
    } >>"$SNAP_DIR/steps.log"
    rm -f "$out_f" "$err_f"
}

setup_base_Fixture() {
    export HOME="$STAGE/home"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
    mkdir -p "$HOME" "$STAGE/bin"
    export GIT_AUTHOR_NAME=tester
    export GIT_AUTHOR_EMAIL=t@t
    export GIT_COMMITTER_NAME=tester
    export GIT_COMMITTER_EMAIL=t@t
    export GIT_AUTHOR_DATE="1700000000 +0000"
    export GIT_COMMITTER_DATE="1700000000 +0000"

    cp "$root_tmp/dump-argv-env" "$STAGE/bin/dump-argv-env"
    chmod +x "$STAGE/bin/dump-argv-env"

    # Install a git wrapper on PATH that records argv[0], bounded args, and full sorted env.
    cat >"$STAGE/bin/git" <<EOF
#!/usr/bin/env bash
"$STAGE/bin/dump-argv-env" "git" "\$0" "\$@" >>"$STAGE/git-invocations.log"
if [ -n "\${FAKE_GIT_READ_STDIN:-}" ] && [[ "\$*" == *"\$FAKE_GIT_READ_STDIN"* ]]; then
    IFS= read -r stdin_line || stdin_line="EOF"
    printf 'git-stdin %s: %s\n' "\$1" "\$stdin_line" >>"$STAGE/git-invocations.log"
fi
if [ -n "\${FAKE_GIT_RM_HERE_ON_CHECK:-}" ] && [[ "\$*" == *"rev-parse --git-dir"* ]]; then
    rmdir "\$FAKE_GIT_RM_HERE_ON_CHECK" 2>/dev/null || true
    exit 0
fi
if [ -n "\${FAKE_GIT_HUGE_DIRTY:-}" ] && [[ "\$*" == *"status --porcelain"* ]]; then
    for ((i = 1; i <= FAKE_GIT_HUGE_DIRTY; i++)); do
        printf ' M dirty_file_number_%05d_with_some_extra_padding_to_exceed_pipe_buffer.txt\n' "\$i"
    done
    exit 0
fi
if [ -n "\${FAKE_GIT_KILL_SIGNAL:-}" ] && [ -n "\${FAKE_GIT_FAIL_MATCH:-}" ] && [[ "\$*" == *"\$FAKE_GIT_FAIL_MATCH"* ]]; then
    kill -"-\$FAKE_GIT_KILL_SIGNAL" \$\$
fi
if [ -n "\${FAKE_GIT_FAIL_MATCH:-}" ] && [[ "\$*" == *"\$FAKE_GIT_FAIL_MATCH"* ]]; then
    echo "fake-git: injected failure for \$*" >&2
    exit "\${FAKE_GIT_FAIL_CODE:-1}"
fi
exec "$REAL_GIT" "\$@"
EOF
    chmod +x "$STAGE/bin/git"

    "$REAL_GIT" config --global init.defaultBranch main
    "$REAL_GIT" config --global advice.detachedHead false

    cat >"$STAGE/agent-app.sh" <<'FAKE'
#!/usr/bin/env bash
stdin_tag=""
if [ -n "${FAKE_AGENT_READ_STDIN:-}" ]; then
    IFS= read -r sline || sline="EOF"
    stdin_tag="|stdin=$sline"
fi
"$STAGE/bin/dump-argv-env" "agent-app${stdin_tag}" "$0" "$@" >>"$FAKE_AGENT_LOG"
if [ "$1" = env ] && [ "$2" = wren ]; then
    echo "export GH_TOKEN=token-for-wren"
    echo "export GIT_AUTHOR_NAME='vitruvian-wren-agent[bot]'"
    echo "export GIT_AUTHOR_EMAIL='4521094+vitruvian-wren-agent[bot]@users.noreply.github.com'"
    echo "export GIT_COMMITTER_NAME='vitruvian-wren-agent[bot]'"
    echo "export GIT_COMMITTER_EMAIL='4521094+vitruvian-wren-agent[bot]@users.noreply.github.com'"
    exit 0
fi
if [ "$1" = env ] && [ "$2" = incomplete ]; then
    echo "export GH_TOKEN=token-for-incomplete"
    echo "export GIT_AUTHOR_NAME='vitruvian-incomplete-agent[bot]'"
    exit 0
fi
if [ "$1" = env ] && [ "$2" = brokenpath ]; then
    echo "export GH_TOKEN=token-for-wren"
    echo "export GIT_AUTHOR_NAME='vitruvian-wren-agent[bot]'"
    echo "export GIT_AUTHOR_EMAIL='4521094+vitruvian-wren-agent[bot]@users.noreply.github.com'"
    echo "export GIT_COMMITTER_NAME='vitruvian-wren-agent[bot]'"
    echo "export GIT_COMMITTER_EMAIL='4521094+vitruvian-wren-agent[bot]@users.noreply.github.com'"
    echo "export PATH=/nonexistent-dir-without-git"
    exit 0
fi
echo "agent-app: unknown agent '$2'" >&2
exit 1
FAKE
    chmod +x "$STAGE/agent-app.sh"
    export AGENT_APP="$STAGE/agent-app.sh"
    export FAKE_AGENT_LOG="$STAGE/agent-app.log"
    : >"$FAKE_AGENT_LOG"
    : >"$STAGE/git-invocations.log"

    "$REAL_GIT" init -q --bare "$STAGE/origin.git"
    "$REAL_GIT" clone -q "$STAGE/origin.git" "$STAGE/repo" 2>/dev/null
    printf 'one\ntwo\nthree\n' >"$STAGE/repo/shared.txt"
    "$REAL_GIT" -C "$STAGE/repo" add shared.txt
    "$REAL_GIT" -C "$STAGE/repo" commit -q -m "chore: base"
    "$REAL_GIT" -C "$STAGE/repo" push -q origin main
    "$REAL_GIT" clone -q "$STAGE/origin.git" "$STAGE/other" 2>/dev/null
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q -b feat/a "$STAGE/wt-a" origin/main 2>/dev/null
}

other_push_main() {
    printf '%s\n' "$2" >"$STAGE/other/$1"
    "$REAL_GIT" -C "$STAGE/other" add "$1"
    "$REAL_GIT" -C "$STAGE/other" commit -q -m "chore: $1 from main"
    "$REAL_GIT" -C "$STAGE/other" push -q origin main
}

snapshot_stage() {
    local snap="$1"
    {
        for r in "$STAGE/origin.git" "$STAGE/repo" "$STAGE/wt-a" "$STAGE/wt-main" "$STAGE/wt-detached" "$STAGE/no-origin"; do
            [ -e "$r" ] || continue
            printf '=== REPO: %s ===\n' "${r#$STAGE/}"
            "$REAL_GIT" -C "$r" for-each-ref --format='%(refname) %(objectname) %(symref)'
            "$REAL_GIT" -C "$r" worktree list --porcelain 2>/dev/null || true
            "$REAL_GIT" -C "$r" log --format='%H|%an|%ae|%cn|%ce|%s|%b' --all 2>/dev/null || true
            if [ "${r%.git}" = "$r" ]; then
                "$REAL_GIT" -C "$r" status --porcelain 2>/dev/null || true
                "$REAL_GIT" -C "$r" diff --cached 2>/dev/null || true
            fi
        done
    } >"$snap/git_state.log"

    (
        cd "$STAGE" &&
        find . \
            -path './home' -prune -o \
            -path './bin' -prune -o \
            -path './rf-bin' -prune -o \
            -path './git-invocations.log' -prune -o \
            -path './agent-app.log' -prune -o \
            -path './secret-scan.log' -prune -o \
            -name '.git' -prune -o \
            -path './origin.git' -prune -o \
            -type f -print | LC_ALL=C sort | while IFS= read -r f; do
            printf '%s  %s\n' "$f" "$(shasum -a 256 "$f" | awk '{print $1}')"
        done
    ) >"$snap/fs_state.log"

    cp "$STAGE/agent-app.log" "$snap/agent-app.log" 2>/dev/null || : >"$snap/agent-app.log"
    cp "$STAGE/secret-scan.log" "$snap/secret-scan.log" 2>/dev/null || : >"$snap/secret-scan.log"
    # In git.sh line 318, `comm -12 <(git diff --cached --name-only HEAD | sort) <(git diff --cached --name-only MERGE_HEAD | sort)`
    # spawns two concurrent process substitutions, so HEAD and MERGE_HEAD may log in either order.
    if [ -f "$STAGE/git-invocations.log" ]; then
        awk '
            /^git <[^<>]*><diff><--cached><--name-only><MERGE_HEAD> / {
                prev = $0
                if ((getline nextline) > 0) {
                    if (nextline ~ /^git <[^<>]*><diff><--cached><--name-only><HEAD> /) {
                        print nextline
                        print prev
                        next
                    } else {
                        print prev
                        print nextline
                        next
                    }
                } else {
                    print prev
                    next
                }
            }
            { print }
        ' "$STAGE/git-invocations.log" >"$snap/git-invocations.log"
    else
        : >"$snap/git-invocations.log"
    fi
}

# Sharded under Bazel (shard_count in BUILD): each shard runs every
# TEST_TOTAL_SHARDS-th scenario, so the suite fits its timeout.
[ -n "${TEST_SHARD_STATUS_FILE:-}" ] && touch "$TEST_SHARD_STATUS_FILE"
SCENARIO_N=0
run_parity_scenario() {
    local name="$1" fn="$2"
    SCENARIO_N=$((SCENARIO_N + 1))
    if [ "$(( (SCENARIO_N - 1) % ${TEST_TOTAL_SHARDS:-1} ))" != "${TEST_SHARD_INDEX:-0}" ]; then
        return 0
    fi
    local snap_rs="$root_tmp/snap_${name}_rs"
    export STAGE="$root_tmp/stage"

    rm -rf "$STAGE" "$snap_rs"
    mkdir -p "$STAGE" "$snap_rs"
    export CURRENT_KIND="rs" SNAP_DIR="$snap_rs"
    ( "$fn" )
    snapshot_stage "$snap_rs"

    local all_ok=1
    for b in "${BASH_BINS[@]}"; do
        local b_tag="${b//\//_}"
        local snap_sh="$root_tmp/snap_${name}_sh_${b_tag}"
        rm -rf "$STAGE" "$snap_sh"
        mkdir -p "$STAGE" "$snap_sh"
        export CURRENT_KIND="sh" SNAP_DIR="$snap_sh" TEST_BASH="$b"
        ( "$fn" )
        snapshot_stage "$snap_sh"

        if ! diff -ru "$snap_sh" "$snap_rs" >"$root_tmp/diff.out" 2>&1; then
            all_ok=0
            fail "$name (vs $b)"
            cat "$root_tmp/diff.out" >&2
        fi
    done

    if [ "$all_ok" -eq 1 ]; then
        pass "$name (verified across ${#BASH_BINS[@]} bash binary/binaries: ${BASH_BINS[*]})"
    fi
}

# ----------------------------------------------------------------------------
# Scenario 1: Help, unknown commands, and outside-git-repo handling
# ----------------------------------------------------------------------------
scenario_help_and_dispatch() {
    setup_base_Fixture
    export PATH="$STAGE/bin:$PATH"
    : >"$STAGE/git-invocations.log"

    step "empty-cmd" "$STAGE/wt-a"
    step "dash-h" "$STAGE/wt-a" -h
    step "dash-dash-help" "$STAGE/wt-a" --help
    step "help-word" "$STAGE/wt-a" help
    step "commit-help" "$STAGE/wt-a" commit --help
    step "push-help" "$STAGE/wt-a" push -h
    step "sync-help" "$STAGE/wt-a" sync --help
    step "unknown-cmd" "$STAGE/wt-a" unknown-subcmd

    mkdir -p "$STAGE/not-a-repo"
    step "not-a-repo-commit" "$STAGE/not-a-repo" commit -m "feat: x"
    step "not-a-repo-unknown" "$STAGE/not-a-repo" bogus
    step_no_bwd "not-a-repo-no-bwd" "$STAGE/not-a-repo" push
    step_no_bwd "in-repo-no-bwd" "$STAGE/wt-a" commit -m "feat: nothing"
}

# ----------------------------------------------------------------------------
# Scenario 2: Commit validation, refusals, and bad arguments
# ----------------------------------------------------------------------------
scenario_commit_validations() {
    setup_base_Fixture
    export PATH="$STAGE/bin:$PATH"

    "$REAL_GIT" clone -q "$STAGE/origin.git" "$STAGE/repo2" 2>/dev/null
    "$REAL_GIT" -C "$STAGE/repo2" checkout -q -b elsewhere
    "$REAL_GIT" -C "$STAGE/repo2" worktree add -q "$STAGE/wt-main" main
    "$REAL_GIT" -C "$STAGE/repo" worktree add -q --detach "$STAGE/wt-detached" origin/main

    : >"$STAGE/git-invocations.log"
    echo x >"$STAGE/repo/x.txt"
    step "primary-checkout" "$STAGE/repo" commit -m "feat: x" x.txt
    rm -f "$STAGE/repo/x.txt"

    echo y >"$STAGE/wt-main/y.txt"
    step "main-in-worktree" "$STAGE/wt-main" commit -m "feat: y" y.txt

    echo z >"$STAGE/wt-detached/z.txt"
    step "detached-head" "$STAGE/wt-detached" commit -m "feat: z" z.txt

    step "nothing-staged" "$STAGE/wt-a" commit -m "feat: nothing"
    echo a >"$STAGE/wt-a/a.txt"
    step "no-message" "$STAGE/wt-a" commit a.txt
    step "non-conventional-1" "$STAGE/wt-a" commit -m "added a file" a.txt
    step "non-conventional-2" "$STAGE/wt-a" commit -m "feat(): empty scope" a.txt
    step "non-conventional-3" "$STAGE/wt-a" commit -m "Revert unquoted" a.txt
    step "amend-refused" "$STAGE/wt-a" commit --amend
    step "no-verify-refused" "$STAGE/wt-a" commit --no-verify
    step "dash-n-refused" "$STAGE/wt-a" commit -n
    step "unknown-flag" "$STAGE/wt-a" commit --bogus
    step "missing-m" "$STAGE/wt-a" commit -m
    step "missing-F" "$STAGE/wt-a" commit -F
    step "missing-fixup" "$STAGE/wt-a" commit --fixup
    step "missing-agent" "$STAGE/wt-a" commit --agent
    step "all-and-paths" "$STAGE/wt-a" commit -m "feat: x" --all a.txt
    step "m-and-F" "$STAGE/wt-a" commit -m "feat: x" -F msg.txt a.txt
    step "fixup-and-m" "$STAGE/wt-a" commit --fixup HEAD -m "feat: x" a.txt
    step "missing-msg-file" "$STAGE/wt-a" commit -F does-not-exist.txt a.txt
    step "missing-msg-file-abs" "$STAGE/wt-a" commit -F "$STAGE/nope.txt" a.txt
    step "fixup-no-such-commit" "$STAGE/wt-a" commit --fixup deadbeefdeadbeef a.txt
    step "fixup-on-main" "$STAGE/wt-a" commit --fixup origin/main a.txt
    step "nonexistent-path" "$STAGE/wt-a" commit -m "feat: x" nonexistent_file.txt

    # Commit on other branch not ancestor of HEAD
    "$REAL_GIT" -C "$STAGE/other" checkout -q -b other-branch
    echo ob >"$STAGE/other/ob.txt"
    "$REAL_GIT" -C "$STAGE/other" add ob.txt
    "$REAL_GIT" -C "$STAGE/other" commit -q -m "feat: other branch"
    ob_sha="$("$REAL_GIT" -C "$STAGE/other" rev-parse HEAD)"
    "$REAL_GIT" -C "$STAGE/wt-a" fetch -q "$STAGE/other" other-branch
    step "fixup-not-ancestor" "$STAGE/wt-a" commit --fixup "$ob_sha" a.txt
}

# ----------------------------------------------------------------------------
# Scenario 3: Commit happy paths, special filenames, --agent, secret scan
# ----------------------------------------------------------------------------
scenario_commit_features() {
    setup_base_Fixture
    export PATH="$STAGE/bin:$PATH"
    : >"$STAGE/git-invocations.log"

    local wt="$STAGE/wt-a"
    echo a >"$wt/a.txt"
    echo b >"$wt/b.txt"
    step "commit-named-with-trailer" "$wt" commit -m "feat(a): add a" -m "Co-Authored-By: Someone <s@example.com>" a.txt

    echo r >"$wt/r.txt"
    step "commit-revert-title" "$wt" commit -m 'Revert "fix: x (#12)"' r.txt

    echo w >"$wt/w.txt"
    step "commit-agent-wren" "$wt" commit --agent wren -m "feat(a): as wren" w.txt

    echo w2 >"$wt/w2.txt"
    step "commit-agent-nobody" "$wt" commit --agent nobody -m "feat(a): as nobody" w2.txt
    step "commit-agent-incomplete" "$wt" commit --agent incomplete -m "feat(a): as incomplete" w2.txt
    AGENT_APP="$STAGE/missing-agent-app.sh" step "commit-missing-agent-app" "$wt" commit --agent wren -m "feat(a): missing app" w2.txt
    rm -f "$wt/w2.txt"

    mkdir -p "$wt/sub"
    echo c >"$wt/sub/c.txt"
    WDIR="$wt/sub" step "commit-subdir-relative" "$wt" commit -m "feat(a): add c" c.txt
    echo d >"$wt/d.txt"
    WDIR="$STAGE/other" step "commit-wdir-outside-here" "$wt" commit -m "feat(a): add d" d.txt

    echo sp >"$wt/-dash and ünicode.txt"
    step "commit-dash-unicode-file" "$wt" commit -m "feat(a)!: special file" -- "-dash and ünicode.txt"

    "$REAL_GIT" -C "$wt" rm -q --cached sub/c.txt >/dev/null
    rm -f "$wt/sub/c.txt"
    printf '# comment header\n\ndocs(a): from a file\n\nBody line.\n' >"$STAGE/msg.txt"
    step "commit-all-and-F" "$wt" commit -F "$STAGE/msg.txt" --all

    plant_secret "$wt/leak.txt"
    step "commit-secret-refused" "$wt" commit -m "feat(a): add leak" leak.txt
    SECRET_SCAN="$STAGE/missing-scan.sh" step "commit-missing-secret-scan" "$wt" commit -m "feat(a): missing scan" leak.txt
    "$REAL_GIT" -C "$wt" rm -q --cached leak.txt
    rm -f "$wt/leak.txt"

    printf '.hidden/\n' >"$wt/.gitignore"
    mkdir -p "$wt/.hidden"
    echo one >"$wt/.hidden/settings.json"
    "$REAL_GIT" -C "$wt" add .gitignore
    "$REAL_GIT" -C "$wt" add -f .hidden/settings.json
    "$REAL_GIT" -C "$wt" commit -q -m "chore(a): hidden settings"
    echo two >"$wt/.hidden/settings.json"
    step "commit-tracked-in-ignored" "$wt" commit -m "fix(a): update hidden" .hidden/settings.json
    echo new >"$wt/.hidden/new.json"
    step "commit-untracked-in-ignored" "$wt" commit -m "feat(a): new hidden" .hidden/new.json
    rm -f "$wt/.hidden/new.json"

    target="$("$REAL_GIT" -C "$wt" log --format=%H --grep='^feat(a): add a$' -1)"
    echo a2 >>"$wt/a.txt"
    step "commit-fixup" "$wt" commit --fixup "$target" a.txt
}

# ----------------------------------------------------------------------------
# Scenario 4: Sync & Merge workflows
# ----------------------------------------------------------------------------
scenario_sync_and_merge() {
    setup_base_Fixture
    export PATH="$STAGE/bin:$PATH"

    local wt="$STAGE/wt-a"
    echo a >"$wt/a.txt"
    step "setup-a" "$wt" commit -m "feat(a): add a" a.txt
    target="$("$REAL_GIT" -C "$wt" rev-parse HEAD)"
    echo a2 >>"$wt/a.txt"
    step "setup-fixup-a" "$wt" commit --fixup "$target" a.txt

    : >"$STAGE/git-invocations.log"

    step "sync-bad-flag" "$wt" sync --bogus
    step "sync-positional-arg" "$wt" sync main
    step "sync-merge-autosquash" "$wt" sync --merge --autosquash
    step "sync-merge-keep-base" "$wt" sync --merge --keep-base
    step "sync-abort-noop" "$wt" sync --abort

    echo dirty >>"$wt/shared.txt"
    step "sync-dirty-refused" "$wt" sync
    "$REAL_GIT" -C "$wt" checkout -q -- shared.txt

    other_push_main main1.txt "from main"
    step "sync-autosquash" "$wt" sync --autosquash
    step "sync-already-up-to-date" "$wt" sync

    # --keep-base before and after pushing to origin
    echo k1 >"$wt/k.txt"
    step "commit-k1" "$wt" commit -m "feat(a): add k" k.txt
    k_sha="$("$REAL_GIT" -C "$wt" rev-parse HEAD)"
    echo k2 >"$wt/k.txt"
    step "commit-fixup-k1" "$wt" commit --fixup "$k_sha" k.txt
    other_push_main k-main.txt "main moved on"
    step "sync-keep-base-unpushed" "$wt" sync --autosquash --keep-base

    step "push-before-second-keep-base" "$wt" push
    k_sha2="$("$REAL_GIT" -C "$wt" rev-parse HEAD)"
    echo k3 >"$wt/k.txt"
    step "commit-fixup-k2" "$wt" commit --fixup "$k_sha2" k.txt
    step "sync-keep-base-pushed" "$wt" sync --autosquash --keep-base
    step "sync-onto-pushed-branch" "$wt" sync

    # Conflict on rebase -> undone
    printf 'one\nTWO from branch\nthree\n' >"$wt/shared.txt"
    step "commit-conflict-branch" "$wt" commit -m "fix(a): change two" shared.txt
    other_push_main shared.txt "$(printf 'one\nTWO from main\nthree')"
    "$REAL_GIT" -C "$wt" fetch -q origin
    "$REAL_GIT" -C "$wt" rebase -q origin/main >/dev/null 2>&1 || true
    step "commit-during-rebase" "$wt" commit -m "fix(a): mid-rebase" shared.txt
    step "push-during-rebase" "$wt" push
    step "sync-during-rebase" "$wt" sync
    step "sync-abort-rebase" "$wt" sync --abort

    step "sync-rebase-conflict-undone" "$wt" sync
    step "sync-merge-conflict-left" "$wt" sync --merge
    step "commit-fixup-during-merge" "$wt" commit --fixup HEAD
    step "push-during-merge" "$wt" push
    step "sync-during-merge" "$wt" sync
    step "commit-unmerged-refused" "$wt" commit
    step "commit-with-markers-refused" "$wt" commit -- shared.txt

    { printf 'one\nTWO from both\nthree\n'; printf 'api_token = "%s"\n' "$SECRET"; } >"$wt/shared.txt"
    step "commit-merge-secret-refused" "$wt" commit -- shared.txt

    printf 'one\nTWO from both\nthree\n' >"$wt/shared.txt"
    "$REAL_GIT" -C "$wt" add shared.txt
    step "commit-merge-conclude" "$wt" commit

    other_push_main main2.txt "more from main"
    step "sync-merge-clean" "$wt" sync --merge

    printf 'one\nTWO again on branch\nthree\n' >"$wt/shared.txt"
    step "commit-again" "$wt" commit -m "fix(a): again" shared.txt
    other_push_main shared.txt "$(printf 'one\nTWO again on main\nthree')"
    step "sync-merge-conflict-2" "$wt" sync --merge
    step "sync-abort-merge" "$wt" sync --abort

    step "sync-rebase-refused-after-merge" "$wt" sync
    step "sync-autosquash-refused-after-merge" "$wt" sync --autosquash
}

# ----------------------------------------------------------------------------
# Scenario 5: Push workflows and injected git failures
# ----------------------------------------------------------------------------
scenario_push_and_failures() {
    setup_base_Fixture
    export PATH="$STAGE/bin:$PATH"

    local wt="$STAGE/wt-a"
    echo p1 >"$wt/p1.txt"
    step "commit-p1" "$wt" commit -m "feat(a): add p1" p1.txt

    : >"$STAGE/git-invocations.log"

    "$REAL_GIT" -C "$STAGE/repo" config push.followTags true
    "$REAL_GIT" -C "$wt" tag -a v9.9.9 -m "a tag" HEAD

    step "push-dry-run" "$wt" push --dry-run
    step "push-happy" "$wt" push

    for f in --force -f --force=x --force-with-lease=x; do
        step "push-force-$f" "$wt" push "$f"
    done
    step "push-unknown-flag" "$wt" push --bogus
    step "push-missing-agent" "$wt" push --agent
    step "push-positional-args" "$wt" push origin main

    "$REAL_GIT" -C "$wt" commit -q --amend -m "feat(a): add p1 reworded"
    step "push-rejected-non-ff" "$wt" push
    step "push-force-with-lease" "$wt" push --force-with-lease

    # Unfetched remote commit on branch rejects --force-with-lease
    "$REAL_GIT" -C "$STAGE/other" fetch -q origin feat/a:feat/a
    "$REAL_GIT" -C "$STAGE/other" checkout -q feat/a
    echo Sneaky >"$STAGE/other/sneaky.txt"
    "$REAL_GIT" -C "$STAGE/other" add sneaky.txt
    "$REAL_GIT" -C "$STAGE/other" commit -q -m "feat(a): sneaky remote commit"
    "$REAL_GIT" -C "$STAGE/other" push -q origin feat/a
    "$REAL_GIT" -C "$wt" commit -q --amend -m "feat(a): local rewrite without fetch"
    step "push-lease-rejected-stale" "$wt" push --force-with-lease
    "$REAL_GIT" -C "$wt" fetch -q origin
    "$REAL_GIT" -C "$wt" reset -q --hard origin/feat/a

    # Secret in unpushed commit blocks push
    plant_secret "$wt/leak.txt"
    "$REAL_GIT" -C "$wt" add leak.txt
    "$REAL_GIT" -C "$wt" commit -q -m "feat(a): oops"
    step "push-secret-blocked" "$wt" push
    "$REAL_GIT" -C "$wt" reset -q --hard HEAD~1

    # Push with --agent wren and --agent nobody
    echo p2 >"$wt/p2.txt"
    step "commit-p2" "$wt" commit -m "feat(a): add p2" p2.txt
    step "push-agent-nobody" "$wt" push --agent nobody
    step "push-agent-wren" "$wt" push --agent wren

    # Injected git failures
    echo p3 >"$wt/p3.txt"
    FAKE_GIT_FAIL_MATCH="commit -q" step "fail-inject-commit" "$wt" commit -m "feat(a): fail commit" p3.txt
    "$REAL_GIT" -C "$wt" reset -q
    FAKE_GIT_FAIL_MATCH="add -A" FAKE_GIT_FAIL_CODE=128 step "fail-inject-add-all" "$wt" commit -m "feat(a): fail add -A" --all
    rm -f "$wt/p3.txt"

    FAKE_GIT_FAIL_MATCH="status --porcelain" FAKE_GIT_FAIL_CODE=128 step "fail-inject-status" "$wt" sync
    FAKE_GIT_FAIL_MATCH="fetch -q origin main" step "fail-inject-fetch" "$wt" sync
    FAKE_GIT_FAIL_MATCH="rev-parse --short origin/main" FAKE_GIT_FAIL_CODE=128 step "fail-inject-rev-parse-onto" "$wt" sync
    FAKE_GIT_FAIL_MATCH="rev-list --merges" FAKE_GIT_FAIL_CODE=128 step "fail-inject-rev-list" "$wt" sync
    FAKE_GIT_FAIL_MATCH="merge -q --no-edit origin/main" step "fail-inject-merge" "$wt" sync --merge
    FAKE_GIT_FAIL_MATCH="rebase -q origin/main" step "fail-inject-rebase" "$wt" sync
    FAKE_GIT_FAIL_MATCH="diff --name-only --diff-filter=U" FAKE_GIT_FAIL_CODE=128 step "fail-inject-conflicted-files" "$wt" sync

    mkdir -p "$STAGE/vanishing-repo"
    FAKE_GIT_RM_HERE_ON_CHECK="$STAGE/vanishing-repo" step "fail-inject-canonicalize-cd" "$STAGE/vanishing-repo" commit -m "feat: x"

    # Stdin inheritance for agent-app and git commit
    echo s1 >"$wt/s1.txt"
    printf 'inherited-agent-stdin\n' | FAKE_AGENT_READ_STDIN=1 step "stdin-inherited-agent" "$wt" commit --agent wren -m "feat(a): stdin agent" s1.txt
    echo s2 >"$wt/s2.txt"
    printf 'inherited-git-stdin\n' | FAKE_GIT_READ_STDIN="commit" step "stdin-inherited-git" "$wt" commit -m "feat(a): stdin git" s2.txt

    # Broken pipe on --help (X1: killed by SIGPIPE=13 -> exit 141 under pipefail, no panic on stderr)
    local bp_err="$STAGE/.bp.err" bp_rc=0
    if [ "$CURRENT_KIND" = "sh" ]; then
        ( set -o pipefail; (sleep 0.05; unset OLDPWD; BUILD_WORKSPACE_DIRECTORY="$wt" "$TEST_BASH" "$SH_BIN" --help) 2>"$bp_err" | : ) || bp_rc=$?
    else
        ( set -o pipefail; (sleep 0.05; unset OLDPWD; BUILD_WORKSPACE_DIRECTORY="$wt" "$RS_BIN" --help) 2>"$bp_err" | : ) || bp_rc=$?
    fi
    {
        printf '=== STEP: broken-pipe-help (rc=%d) ===\n' "$bp_rc"
        printf -- '--- stderr ---\n'
        normalize_stderr "$bp_err"
        printf '\n'
    } >>"$SNAP_DIR/steps.log"
    rm -f "$bp_err"

    # Repo without origin remote
    "$REAL_GIT" init -q "$STAGE/no-origin"
    echo init >"$STAGE/no-origin/f.txt"
    "$REAL_GIT" -C "$STAGE/no-origin" add f.txt
    "$REAL_GIT" -C "$STAGE/no-origin" commit -q -m "chore: init"
    "$REAL_GIT" -C "$STAGE/no-origin" worktree add -q -b feat/x "$STAGE/no-origin-wt"
    step "push-no-origin" "$STAGE/no-origin-wt" push
}

# ----------------------------------------------------------------------------
# Scenario 6: UTF-8 locale collation and binary conflict markers
# ----------------------------------------------------------------------------
scenario_utf8_locale_and_binary_markers() {
    setup_base_Fixture
    export PATH="$STAGE/bin:$PATH"
    local wt="$STAGE/wt-a"

    # Base files with names that order differently in C vs UTF-8 locales, plus a binary file
    local names=("A0" "A_0" "AB" "A_B" "AC" "a-b" "A-c" "a_b" "x/f.txt" "x_y/f.txt")
    mkdir -p "$STAGE/other/x" "$STAGE/other/x_y"
    for n in "${names[@]}"; do
        printf 'base\n' >"$STAGE/other/$n"
        "$REAL_GIT" -C "$STAGE/other" add "$n"
    done
    printf '\x00base-bin\n' >"$STAGE/other/bin.dat"
    "$REAL_GIT" -C "$STAGE/other" add bin.dat
    "$REAL_GIT" -C "$STAGE/other" commit -q -m "chore: add collation and binary base files"
    "$REAL_GIT" -C "$STAGE/other" push -q origin main

    "$REAL_GIT" -C "$wt" fetch -q origin main
    "$REAL_GIT" -C "$wt" rebase -q origin/main

    # Diverge on branch
    for n in "${names[@]}"; do
        printf 'branch-%s\n' "$n" >"$wt/$n"
        "$REAL_GIT" -C "$wt" add "$n"
    done
    printf '\x00branch-bin\n' >"$wt/bin.dat"
    "$REAL_GIT" -C "$wt" add bin.dat
    "$REAL_GIT" -C "$wt" commit -q -m "feat(a): branch changes"

    # Diverge on main
    for n in "${names[@]}"; do
        printf 'main-%s\n' "$n" >"$STAGE/other/$n"
        "$REAL_GIT" -C "$STAGE/other" add "$n"
    done
    printf '\x00main-bin\n' >"$STAGE/other/bin.dat"
    "$REAL_GIT" -C "$STAGE/other" add bin.dat
    "$REAL_GIT" -C "$STAGE/other" commit -q -m "chore: main conflicting changes"
    "$REAL_GIT" -C "$STAGE/other" push -q origin main

    : >"$STAGE/git-invocations.log"

    # Start conflicted merge
    step "merge-conflict-collation" "$wt" sync --merge

    # Stage all text files and the binary file with conflict markers still inside
    for n in "${names[@]}"; do
        printf '<<<<<<< HEAD\nbranch-%s\n||||||| base\nbase\n=======\nmain-%s\n>>>>>>> origin/main\n' "$n" "$n" >"$wt/$n"
        "$REAL_GIT" -C "$wt" add "$n"
    done
    printf '\x00binary-header\n<<<<<<< HEAD\nbranch-bin\n=======\nmain-bin\n>>>>>>> origin/main\n' >"$wt/bin.dat"
    "$REAL_GIT" -C "$wt" add bin.dat

    if locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
        LC_ALL=en_US.UTF-8 step "commit-markers-utf8-locale" "$wt" commit
    else
        echo "note: skipping en_US.UTF-8 locale sub-step (not in locale -a)"
        LC_ALL=C step "commit-markers-c-locale-fallback" "$wt" commit
    fi
    LC_ALL=C step "commit-markers-c-locale" "$wt" commit

    step "abort-collation-merge" "$wt" sync --abort
}

# ----------------------------------------------------------------------------
# Scenario 7: Non-UTF-8 commit message bytes, -F files, and path arguments
# ----------------------------------------------------------------------------
scenario_non_utf8_bytes() {
    setup_base_Fixture
    export PATH="$STAGE/bin:$PATH"
    local wt="$STAGE/wt-a"
    : >"$STAGE/git-invocations.log"

    local raw_valid_msg raw_bad_msg raw_path
    raw_valid_msg="$(printf 'feat(a): raw \xff\xfe bytes in message')"
    raw_bad_msg="$(printf 'not conventional \xff\xfe subject')"
    raw_path="$(printf 'nonutf8_\xff.txt')"

    echo u1 >"$wt/u1.txt"
    LC_ALL=C step "non-utf8-bad-subject" "$wt" commit -m "$raw_bad_msg" u1.txt
    LC_ALL=C step "non-utf8-valid-subject-m" "$wt" commit -m "$raw_valid_msg" u1.txt

    echo u2 >"$wt/u2.txt"
    printf '# comment \xff\nfeat(a): from file \xff\xfe line\n\nBody \x80\xff.\n' >"$STAGE/raw-msg.txt"
    LC_ALL=C step "non-utf8-valid-subject-F" "$wt" commit -F "$STAGE/raw-msg.txt" u2.txt

    # Non-UTF-8 path argument (created if filesystem permits, otherwise refused on staging with exact bytes)
    ( echo u3 >"$wt/$raw_path" ) 2>/dev/null || true
    LC_ALL=C step "non-utf8-path-arg" "$wt" commit -m "feat(a): non-utf8 path" -- "$raw_path"
}

# ----------------------------------------------------------------------------
# Scenario 8: Write errors (>&-, 2>&-, /dev/full, SIGPIPE ignored), signals,
# command not found, and >64KiB dirty pipeline output
# ----------------------------------------------------------------------------
step_closed_stdout() {
    local label="$1" wt="$2"; shift 2
    local err_f="$STAGE/.step.err" rc=0
    if [ "$CURRENT_KIND" = "sh" ]; then
        (cd "$STAGE" && unset OLDPWD && BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$TEST_BASH" "$SH_BIN" "$@" >&-) 2>"$err_f" || rc=$?
    else
        (cd "$STAGE" && unset OLDPWD && BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$RS_BIN" "$@" >&-) 2>"$err_f" || rc=$?
    fi
    {
        printf '=== STEP: %s (rc=%d) ===\n' "$label" "$rc"
        printf -- '--- stderr ---\n'
        normalize_stderr "$err_f"
        printf '\n'
    } >>"$SNAP_DIR/steps.log"
    rm -f "$err_f"
}

step_closed_stderr() {
    local label="$1" wt="$2"; shift 2
    local out_f="$STAGE/.step.out" rc=0
    if [ "$CURRENT_KIND" = "sh" ]; then
        (cd "$STAGE" && unset OLDPWD && BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$TEST_BASH" "$SH_BIN" "$@" 2>&-) >"$out_f" || rc=$?
    else
        (cd "$STAGE" && unset OLDPWD && BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$RS_BIN" "$@" 2>&-) >"$out_f" || rc=$?
    fi
    {
        printf '=== STEP: %s (rc=%d) ===\n' "$label" "$rc"
        printf -- '--- stdout ---\n'
        cat "$out_f"
        printf '\n'
    } >>"$SNAP_DIR/steps.log"
    rm -f "$out_f"
}

step_sigpipe_ignored_head1() {
    local label="$1" wt="$2"; shift 2
    local out_f="$STAGE/.step.out" err_f="$STAGE/.step.err" rc=0
    if [ "$CURRENT_KIND" = "sh" ]; then
        (
            set -o pipefail
            trap '' PIPE
            cd "$STAGE" && unset OLDPWD && BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$TEST_BASH" "$SH_BIN" "$@" 2>"$err_f" | head -n 1 >"$out_f"
        ) || rc=$?
    else
        (
            set -o pipefail
            trap '' PIPE
            cd "$STAGE" && unset OLDPWD && BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$RS_BIN" "$@" 2>"$err_f" | head -n 1 >"$out_f"
        ) || rc=$?
    fi
    {
        printf '=== STEP: %s (rc=%d) ===\n' "$label" "$rc"
        printf -- '--- stdout ---\n'
        cat "$out_f"
        printf -- '--- stderr ---\n'
        normalize_stderr "$err_f"
        printf '\n'
    } >>"$SNAP_DIR/steps.log"
    rm -f "$out_f" "$err_f"
}

scenario_write_errors_and_signals() {
    setup_base_Fixture
    export PATH="$STAGE/bin:$PATH"
    local wt="$STAGE/wt-a"
    : >"$STAGE/git-invocations.log"

    # Use a silent SECRET_SCAN (/usr/bin/true) for closed-stdout / /dev/full checks so
    # secret-scan's own stdout echo doesn't abort before git.sh reaches lines 360/417/436/437.
    # 1. commit >&- : commits the file, then fails at line 360 (`echo: write error: Bad file descriptor`) and exits 1
    echo c1 >"$wt/c_closed.txt"
    local head_before_commit head_after_commit
    head_before_commit="$("$REAL_GIT" -C "$wt" rev-parse HEAD)"
    SECRET_SCAN=/usr/bin/true step_closed_stdout "commit-closed-stdout" "$wt" commit -m "feat(a): closed stdout commit" c_closed.txt
    head_after_commit="$("$REAL_GIT" -C "$wt" rev-parse HEAD)"
    if [ "$head_before_commit" = "$head_after_commit" ]; then
        printf 'BUG: commit >&- did not record commit!\n' >>"$SNAP_DIR/steps.log"
    fi

    # 2. push --agent wren >&- : fails at line 417 (`echo: write error: Bad file descriptor`) and exits 1 BEFORE pushing!
    local origin_refs_before
    origin_refs_before="$("$REAL_GIT" -C "$STAGE/origin.git" for-each-ref)"
    SECRET_SCAN=/usr/bin/true step_closed_stdout "push-agent-closed-stdout" "$wt" push --agent wren
    local origin_refs_after
    origin_refs_after="$("$REAL_GIT" -C "$STAGE/origin.git" for-each-ref)"
    if [ "$origin_refs_before" != "$origin_refs_after" ]; then
        printf 'BUG: push --agent wren >&- mutated origin refs!\n' >>"$SNAP_DIR/steps.log"
    fi

    # 3. push --dry-run >&- (fails at line 436) and push >&- (pushes, then fails at line 437)
    SECRET_SCAN=/usr/bin/true step_closed_stdout "push-dry-closed-stdout" "$wt" push --dry-run
    SECRET_SCAN=/usr/bin/true step_closed_stdout "push-closed-stdout" "$wt" push
    local origin_refs_after_plain_push
    origin_refs_after_plain_push="$("$REAL_GIT" -C "$STAGE/origin.git" for-each-ref)"
    if [ "$origin_refs_before" = "$origin_refs_after_plain_push" ]; then
        printf 'BUG: plain push >&- did not update origin refs before line 437 echo!\n' >>"$SNAP_DIR/steps.log"
    fi

    # 4. sync --abort >&- (fails at line 466) and sync >&- (already up-to-date, fails at line 538)
    step_closed_stdout "sync-abort-closed-stdout" "$wt" sync --abort
    step_closed_stdout "sync-up-to-date-closed-stdout" "$wt" sync

    # 5. Closed stderr (2>&-) on bad_args (line 107 write error -> exits 1 under set -e!) and refuse (line 99 -> exits 1)
    step_closed_stderr "bad-args-closed-stderr" "$wt" commit --bogus
    step_closed_stderr "refuse-closed-stderr" "$wt" commit --amend

    # 6. /dev/full (Linux only; skip with note on macOS where /dev/full does not exist)
    if [ -w /dev/full ]; then
        local df_err="$STAGE/.df.err" df_rc=0
        echo df1 >"$wt/df1.txt"
        if [ "$CURRENT_KIND" = "sh" ]; then
            (cd "$STAGE" && unset OLDPWD && BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$TEST_BASH" "$SH_BIN" commit -m "feat(a): dev full" df1.txt >/dev/full) 2>"$df_err" || df_rc=$?
        else
            (cd "$STAGE" && unset OLDPWD && BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$RS_BIN" commit -m "feat(a): dev full" df1.txt >/dev/full) 2>"$df_err" || df_rc=$?
        fi
        {
            printf '=== STEP: commit-dev-full (rc=%d) ===\n' "$df_rc"
            printf -- '--- stderr ---\n'
            normalize_stderr "$df_err"
            printf '\n'
        } >>"$SNAP_DIR/steps.log"
        rm -f "$df_err"
    else
        printf '=== STEP: dev-full-note ===\nnote: skipping /dev/full write-error check (not available on %s)\n\n' "$(uname -s)" >>"$SNAP_DIR/steps.log"
    fi

    # 7. SIGPIPE ignored at entry (`(trap '' PIPE; <cmd> | head -n 1)`) -> EPIPE write error on 2nd stdout line
    echo sp1 >"$wt/sp1.txt"
    step_sigpipe_ignored_head1 "commit-sigpipe-ignored" "$wt" commit -m "feat(a): sigpipe ignored" sp1.txt
    step_sigpipe_ignored_head1 "push-agent-sigpipe-ignored" "$wt" push --agent wren

    # 8. Child killed by signals -> 128+signal (SIGTERM=15 -> 143, SIGKILL=9 -> 137, SIGPIPE=13 -> 141)
    echo sig >"$wt/sig.txt"
    FAKE_GIT_FAIL_MATCH="add -A" FAKE_GIT_KILL_SIGNAL=TERM step "child-killed-sigterm-add" "$wt" commit -m "feat(a): sigterm" --all
    FAKE_GIT_FAIL_MATCH="add -A" FAKE_GIT_KILL_SIGNAL=KILL step "child-killed-sigkill-add" "$wt" commit -m "feat(a): sigkill" --all
    rm -f "$wt/sig.txt"
    FAKE_GIT_FAIL_MATCH="status --porcelain" FAKE_GIT_KILL_SIGNAL=TERM step "child-killed-sigterm-status" "$wt" sync
    FAKE_GIT_FAIL_MATCH="path-format=absolute --git-dir" FAKE_GIT_KILL_SIGNAL=PIPE step "child-killed-sigpipe-git-dir" "$wt" sync

    # 9. `git: command not found` at line 427 when agent-app sets PATH without git
    echo bp >"$wt/bp.txt"
    step "commit-bp" "$wt" commit -m "feat(a): before broken path push" bp.txt
    step "push-git-command-not-found" "$wt" push --agent brokenpath

    # 10. >64KiB of dirty output in `sync`:
    #   - With default SIGPIPE: `printf | head -20 | sed` at line 487 dies with 141 mid-message under pipefail.
    #   - With SIGPIPE ignored: `printf` at line 487 prints `line 487: printf: write error: Broken pipe` and exits 1.
    FAKE_GIT_HUGE_DIRTY=4000 step "sync-huge-dirty-default-sigpipe" "$wt" sync
    local hd_err="$STAGE/.hd.err" hd_rc=0
    if [ "$CURRENT_KIND" = "sh" ]; then
        (trap '' PIPE; cd "$STAGE" && unset OLDPWD && FAKE_GIT_HUGE_DIRTY=4000 BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$TEST_BASH" "$SH_BIN" sync) 2>"$hd_err" || hd_rc=$?
    else
        (trap '' PIPE; cd "$STAGE" && unset OLDPWD && FAKE_GIT_HUGE_DIRTY=4000 BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$RS_BIN" sync) 2>"$hd_err" || hd_rc=$?
    fi
    {
        printf '=== STEP: sync-huge-dirty-sigpipe-ignored (rc=%d) ===\n' "$hd_rc"
        printf -- '--- stderr ---\n'
        normalize_stderr "$hd_err" | grep -v ': line 487: printf: write error:' || true
        normalize_stderr "$hd_err" | grep ': line 487: printf: write error:' || true
        printf '\n'
    } >>"$SNAP_DIR/steps.log"
    rm -f "$hd_err"
}

# ----------------------------------------------------------------------------
# Scenario 9: Runfiles discovery parity (manifest-only, directory-only, and
# both-present layouts, verifying env & GITLEAKS/SECRET_SCAN/AGENT_APP text)
# ----------------------------------------------------------------------------
scenario_runfiles_layouts() {
    setup_base_Fixture
    export PATH="$STAGE/bin:$PATH"
    local wt="$STAGE/wt-a"
    : >"$STAGE/git-invocations.log"
    : >"$STAGE/secret-scan.log"

    if [ -z "$REAL_RUNFILES_BASH" ] || [ ! -f "$REAL_RUNFILES_BASH" ]; then
        printf '=== STEP: runfiles-skip ===\nnote: runfiles.bash not found\n' >>"$SNAP_DIR/steps.log"
        return 0
    fi

    mkdir -p "$STAGE/rf-bin" "$STAGE/rf-targets"
    local tool_bin="$STAGE/rf-bin/git-tool"
    if [ "$CURRENT_KIND" = "sh" ]; then
        cp "$SH_BIN" "$tool_bin"
    else
        cp "$RS_BIN" "$tool_bin"
    fi
    chmod +x "$tool_bin"

    # Create fake tools for manifest targets AND directory targets in distinct paths
    # so we can tell whether manifest or directory was chosen when both exist.
    mkdir -p "$STAGE/rf-targets/manifest" "$STAGE/rf-targets/dir"
    for sub in manifest dir; do
        cat >"$STAGE/rf-targets/$sub/secret-scan.sh" <<EOF
#!/usr/bin/env bash
if [ "\${CURRENT_KIND:-}" = "rs" ] && [ -n "\${RUNFILES_REPO_MAPPING+x}" ]; then
    echo "ERROR: Rust exported RUNFILES_REPO_MAPPING=\$RUNFILES_REPO_MAPPING" >&2
    exit 99
fi
"$STAGE/bin/dump-argv-env" "secret-scan($sub)" "\$0" "\$@" >>"$STAGE/secret-scan.log"
exit 0
EOF
        chmod +x "$STAGE/rf-targets/$sub/secret-scan.sh"
        printf '#!/usr/bin/env bash\nexit 0\n' >"$STAGE/rf-targets/$sub/gitleaks"
        chmod +x "$STAGE/rf-targets/$sub/gitleaks"
        printf '# config (%s)\n' "$sub" >"$STAGE/rf-targets/$sub/.gitleaks.toml"
        cp "$STAGE/agent-app.sh" "$STAGE/rf-targets/$sub/agent-app.sh"
    done

    cat >"$STAGE/rf-targets/_repo_mapping" <<'EOF'
,bazel_tools,bazel_tools
,multitool,rules_multitool++multitool+multitool
,vitruvian_core,_main
EOF

    # Helper to invoke $tool_bin with RUNFILES_DIR, RUNFILES_MANIFEST_FILE, SECRET_SCAN,
    # GITLEAKS, GITLEAKS_CONFIG, AGENT_APP unset so runfiles discovery runs from $0.
    run_rf_step() {
        local label="$1"; shift
        local out_f="$STAGE/.step.out" err_f="$STAGE/.step.err" rc=0
        if [ "$CURRENT_KIND" = "sh" ]; then
            (
                cd "$STAGE"
                unset OLDPWD RUNFILES_DIR RUNFILES_MANIFEST_FILE RUNFILES_REPO_MAPPING SECRET_SCAN GITLEAKS GITLEAKS_CONFIG AGENT_APP
                BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$TEST_BASH" "$tool_bin" "$@"
            ) >"$out_f" 2>"$err_f" || rc=$?
        else
            (
                cd "$STAGE"
                unset OLDPWD RUNFILES_DIR RUNFILES_MANIFEST_FILE RUNFILES_REPO_MAPPING SECRET_SCAN GITLEAKS GITLEAKS_CONFIG AGENT_APP
                BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$tool_bin" "$@"
            ) >"$out_f" 2>"$err_f" || rc=$?
        fi
        {
            printf '=== STEP: %s (rc=%d) ===\n' "$label" "$rc"
            printf -- '--- stdout ---\n'
            cat "$out_f"
            printf -- '--- stderr ---\n'
            ACTIVE_BIN="$tool_bin" normalize_stderr "$err_f"
            printf '\n'
        } >>"$SNAP_DIR/steps.log"
        rm -f "$out_f" "$err_f"
    }

    # Layout A: manifest-only ($0.runfiles_manifest)
    cat >"${tool_bin}.runfiles_manifest" <<EOF
_repo_mapping $STAGE/rf-targets/_repo_mapping
bazel_tools/tools/bash/runfiles/runfiles.bash $REAL_RUNFILES_BASH
_main/tools/secret-scan/secret-scan.sh $STAGE/rf-targets/manifest/secret-scan.sh
rules_multitool++multitool+multitool/tools/gitleaks/gitleaks $STAGE/rf-targets/manifest/gitleaks
_main/.gitleaks.toml $STAGE/rf-targets/manifest/.gitleaks.toml
_main/tools/agent-app/agent-app.sh $STAGE/rf-targets/manifest/agent-app.sh
EOF
    echo rf1 >"$wt/rf1.txt"
    run_rf_step "runfiles-manifest-only-commit" commit --agent wren -m "feat(a): manifest layout" rf1.txt

    # Layout B: directory-only ($0.runfiles, no manifest)
    rm -f "${tool_bin}.runfiles_manifest"
    mkdir -p \
        "${tool_bin}.runfiles/bazel_tools/tools/bash/runfiles" \
        "${tool_bin}.runfiles/_main/tools/secret-scan" \
        "${tool_bin}.runfiles/_main/tools/agent-app" \
        "${tool_bin}.runfiles/rules_multitool++multitool+multitool/tools/gitleaks"
    cp "$REAL_RUNFILES_BASH" "${tool_bin}.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash"
    cp "$STAGE/rf-targets/_repo_mapping" "${tool_bin}.runfiles/_repo_mapping"
    cp "$STAGE/rf-targets/dir/secret-scan.sh" "${tool_bin}.runfiles/_main/tools/secret-scan/secret-scan.sh"
    cp "$STAGE/rf-targets/dir/gitleaks" "${tool_bin}.runfiles/rules_multitool++multitool+multitool/tools/gitleaks/gitleaks"
    cp "$STAGE/rf-targets/dir/.gitleaks.toml" "${tool_bin}.runfiles/_main/.gitleaks.toml"
    cp "$STAGE/rf-targets/dir/agent-app.sh" "${tool_bin}.runfiles/_main/tools/agent-app/agent-app.sh"
    echo rf2 >"$wt/rf2.txt"
    run_rf_step "runfiles-dir-only-commit" commit --agent wren -m "feat(a): dir layout" rf2.txt

    # Layout C: both $0.runfiles_manifest and $0.runfiles exist (like `bazel run` in bazel-bin);
    # runfiles.bash prefers $0.runfiles_manifest over $0.runfiles.
    cat >"${tool_bin}.runfiles_manifest" <<EOF
_repo_mapping $STAGE/rf-targets/_repo_mapping
bazel_tools/tools/bash/runfiles/runfiles.bash $REAL_RUNFILES_BASH
_main/tools/secret-scan/secret-scan.sh $STAGE/rf-targets/manifest/secret-scan.sh
rules_multitool++multitool+multitool/tools/gitleaks/gitleaks $STAGE/rf-targets/manifest/gitleaks
_main/.gitleaks.toml $STAGE/rf-targets/manifest/.gitleaks.toml
_main/tools/agent-app/agent-app.sh $STAGE/rf-targets/manifest/agent-app.sh
EOF
    echo rf3 >"$wt/rf3.txt"
    run_rf_step "runfiles-both-prefers-manifest" commit --agent wren -m "feat(a): both layout" rf3.txt
}

# ----------------------------------------------------------------------------
# Explicit KEEP-SAFE test (Item 4): Conflict-marker check on filenames with
# `|` or `&` where git.sh's `sed "s|^|${f}:|"` fails/mangles while Rust refuses
# ----------------------------------------------------------------------------
test_keep_safe_conflict_marker_filenames() {
    export STAGE="$root_tmp/stage_keepsafe"
    rm -rf "$STAGE"
    mkdir -p "$STAGE"
    (
        setup_base_Fixture
        export PATH="$STAGE/bin:$PATH"
        local wt="$STAGE/wt-a"

        # Add base files `a|b.txt` and `a&b.txt` on main
        printf 'base\n' >"$STAGE/other/a|b.txt"
        printf 'base\n' >"$STAGE/other/a&b.txt"
        "$REAL_GIT" -C "$STAGE/other" add "a|b.txt" "a&b.txt"
        "$REAL_GIT" -C "$STAGE/other" commit -q -m "chore: base special names"
        "$REAL_GIT" -C "$STAGE/other" push -q origin main

        "$REAL_GIT" -C "$wt" fetch -q origin main
        "$REAL_GIT" -C "$wt" rebase -q origin/main

        # Diverge on branch and main for `a|b.txt`
        printf 'branch\n' >"$wt/a|b.txt"
        "$REAL_GIT" -C "$wt" add "a|b.txt"
        "$REAL_GIT" -C "$wt" commit -q -m "feat(a): branch pipe file"

        printf 'main\n' >"$STAGE/other/a|b.txt"
        "$REAL_GIT" -C "$STAGE/other" add "a|b.txt"
        "$REAL_GIT" -C "$STAGE/other" commit -q -m "chore: main pipe file"
        "$REAL_GIT" -C "$STAGE/other" push -q origin main

        "$REAL_GIT" -C "$wt" fetch -q origin main
        "$REAL_GIT" -C "$wt" merge -q --no-edit origin/main >/dev/null 2>&1 || true

        # Stage `a|b.txt` WITH conflict markers still present
        printf '<<<<<<< HEAD\nbranch\n=======\nmain\n>>>>>>> origin/main\n' >"$wt/a|b.txt"
        "$REAL_GIT" -C "$wt" add "a|b.txt"

        # 1. Verify Rust refuses `a|b.txt` with literal `a|b.txt:1`
        local rs_err="$STAGE/rs_pipe.err" rs_rc=0
        BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$RS_BIN" commit >"$STAGE/rs_pipe.out" 2>"$rs_err" || rs_rc=$?
        if [ "$rs_rc" -ne 1 ] || ! grep -Fq "    a|b.txt:1" "$rs_err"; then
            echo "KEEP-SAFE check failed: expected Rust to refuse conflict markers in a|b.txt (rc=$rs_rc)" >&2
            cat "$rs_err" >&2
            exit 1
        fi

        # 2. Verify bash git.sh lets `a|b.txt` be committed (rc=0) because `sed "s|^|${f}:|"` fails under `|| true`
        local sh_rc=0
        BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$TEST_BASH" "$SH_BIN" commit >"$STAGE/sh_pipe.out" 2>"$STAGE/sh_pipe.err" || sh_rc=$?
        if [ "$sh_rc" -ne 0 ]; then
            echo "KEEP-SAFE check failed: expected git.sh to allow a|b.txt due to sed delimiter bug (rc=$sh_rc)" >&2
            exit 1
        fi

        # 3. Now diverge on `a&b.txt` and verify Rust outputs literal `a&b.txt:1` while bash mangles `&`
        printf 'branch\n' >"$wt/a&b.txt"
        "$REAL_GIT" -C "$wt" add "a&b.txt"
        "$REAL_GIT" -C "$wt" commit -q -m "feat(a): branch amp file"

        printf 'main\n' >"$STAGE/other/a&b.txt"
        "$REAL_GIT" -C "$STAGE/other" add "a&b.txt"
        "$REAL_GIT" -C "$STAGE/other" commit -q -m "chore: main amp file"
        "$REAL_GIT" -C "$STAGE/other" push -q origin main

        "$REAL_GIT" -C "$wt" fetch -q origin main
        "$REAL_GIT" -C "$wt" merge -q --no-edit origin/main >/dev/null 2>&1 || true
        printf '<<<<<<< HEAD\nbranch\n=======\nmain\n>>>>>>> origin/main\n' >"$wt/a&b.txt"
        "$REAL_GIT" -C "$wt" add "a&b.txt"

        local rs_amp_err="$STAGE/rs_amp.err" rs_amp_rc=0
        BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$RS_BIN" commit >"$STAGE/rs_amp.out" 2>"$rs_amp_err" || rs_amp_rc=$?
        local sh_amp_err="$STAGE/sh_amp.err" sh_amp_rc=0
        BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="$wt" "$TEST_BASH" "$SH_BIN" commit >"$STAGE/sh_amp.out" 2>"$sh_amp_err" || sh_amp_rc=$?

        if [ "$rs_amp_rc" -ne 1 ] || ! grep -Fq "    a&b.txt:1" "$rs_amp_err"; then
            echo "KEEP-SAFE check failed: expected Rust to report literal a&b.txt:1" >&2
            cat "$rs_amp_err" >&2
            exit 1
        fi
        if [ "$sh_amp_rc" -ne 1 ] || grep -Fq "    a&b.txt:1" "$sh_amp_err"; then
            echo "KEEP-SAFE check failed: expected git.sh to mangle '&' in a&b.txt" >&2
            cat "$sh_amp_err" >&2
            exit 1
        fi
    )
    if [ $? -eq 0 ]; then
        pass "keep_safe_conflict_marker_filenames (| and &)"
    else
        fail "keep_safe_conflict_marker_filenames (| and &)"
    fi
}

echo "git_parity_test"
run_parity_scenario "help_and_dispatch" scenario_help_and_dispatch
run_parity_scenario "commit_validations" scenario_commit_validations
run_parity_scenario "commit_features" scenario_commit_features
run_parity_scenario "sync_and_merge" scenario_sync_and_merge
run_parity_scenario "push_and_failures" scenario_push_and_failures
run_parity_scenario "utf8_locale_and_binary_markers" scenario_utf8_locale_and_binary_markers
run_parity_scenario "non_utf8_bytes" scenario_non_utf8_bytes
run_parity_scenario "write_errors_and_signals" scenario_write_errors_and_signals
run_parity_scenario "runfiles_layouts" scenario_runfiles_layouts
[ "${TEST_SHARD_INDEX:-0}" = 0 ] && test_keep_safe_conflict_marker_filenames

echo "git_parity_test: $pass_n passed, $fail_n failed"
[ "$fail_n" -eq 0 ]
