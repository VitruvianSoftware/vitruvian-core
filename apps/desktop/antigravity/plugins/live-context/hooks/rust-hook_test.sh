#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Tests rust-hook.sh, the launcher every hook in hooks.json goes through, on a
# copy of this plugin's folder:
#
# - with Bazel's own rustc (RUST_HOOK_RUSTC, from BUILD) it builds the real
#   hooks/src in the background and each hook then answers, as a fresh
#   install would;
# - with a stub rustc: the build is detached and survives the host killing
#   the hook's process group; it builds in a private folder and renames;
#   rustc's output reaches the log; the binary is reused; any change to the
#   launcher or to any file in hooks/src (src/bin too) rebuilds; a failed
#   build backs off, then is retried;
# - every failure answers with the hook's fallback JSON and exits 0: no
#   rustc, a failed build, a garbage or deleted cached binary, an unsafe
#   cache folder;
# - every hooks.json command exists, and names a crate and source that exist.
#
# The test is identical in every plugin; plugin-specific checks are in the
# hook's own Rust tests.

set -u

fails=0
check() {
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"
		echo "  want: $3"
		echo "  got:  $2"
		fails=$((fails + 1))
	fi
}
contains() {
	case "$2" in
	*"$3"*) echo "ok   $1" ;;
	*)
		echo "FAIL $1"
		echo "  want text: $3"
		echo "  got:       $2"
		fails=$((fails + 1))
		;;
	esac
}

# Set by BUILD: Bazel's rustc and the plugin's folder name.
: "${REAL_RUSTC:?}" "${PLUGIN_NAME:?}"
real_rustc=$(cd "$(dirname "$REAL_RUSTC")" && pwd)/$(basename "$REAL_RUSTC")
# HOOKS_JSON (from BUILD) locates the plugin; by default, beside this file.
hooks_json=${HOOKS_JSON:-$(dirname "$0")/../hooks.json}
plugin_src=$(cd "$(dirname "$hooks_json")" && pwd)
plugin_name=$PLUGIN_NAME
tmp=${TEST_TMPDIR:-$(mktemp -d)}
plugin="$tmp/$plugin_name"
rm -rf "$plugin"
mkdir -p "$plugin"
# -L: the runfiles are links to the sources, which the test edits.
cp -RL "$plugin_src/hooks" "$plugin/hooks"
cp "$plugin_src/hooks.json" "$plugin/hooks.json"
chmod -R u+w "$plugin"

export HOME="$tmp/home"
export XDG_CACHE_HOME="$tmp/cache"
export ANTIGRAVITY_APP_DATA_DIR="$tmp/app"
mkdir -p "$HOME" "$ANTIGRAVITY_APP_DATA_DIR/live-context-state"
# Keep live-context's hook off the network: no git or gh probes.
echo '{"injectGit":false,"injectGitHub":false}' \
	>"$ANTIGRAVITY_APP_DATA_DIR/live-context-state/settings.json"
cache="$XDG_CACHE_HOME/antigravity-plugins"

# The hook scripts named in hooks.json, each with the crate, source and
# fallback it hands to rust-hook.sh.
hooks=$(sed -n 's/.*"command": *"\.\/\(hooks\/[^"]*\)".*/\1/p' "$plugin/hooks.json" | sort -u)
[ -n "$hooks" ] || {
	echo "FAIL hooks.json names no hooks"
	exit 1
}
first=$(echo "$hooks" | head -n 1)

main_of() { sed -n 's/.*rust-hook\.sh" [a-z_]* \([^ ]*\.rs\).*/\1/p' "$plugin/$1"; }
name_of() { basename "$(main_of "$1")" .rs; }
fallback_of() { sed -n "s/^[[:space:]]*'\(.*\)'[[:space:]]*\$/\1/p" "$plugin/$1"; }

for h in $hooks; do
	[ -x "$plugin/$h" ] && ok=0 || ok=1
	check "$h is executable" "$ok" "0"
	crate=$(sed -n 's/.*rust-hook\.sh" \([a-z_]*\) \([^ ]*\.rs\).*/\1/p' "$plugin/$h")
	main=$(main_of "$h")
	[ -n "$crate" ] && [ -f "$plugin/hooks/src/$main" ] && ok=0 || ok=1
	check "$h runs an existing source (src/$main)" "$ok" "0"
	grep -q "$crate::" "$plugin/hooks/src/$main" && ok=0 || ok=1
	check "src/$main uses crate $crate" "$ok" "0"
done

run_hook() { # run_hook <hook script> <stdin>; sets $status $out $err
	printf '%s' "$2" | (cd "$plugin" && sh -c "./$1") >"$tmp/out" 2>"$tmp/err"
	status=$?
	out=$(cat "$tmp/out")
	err=$(cat "$tmp/err")
}

# A hook's cached binaries, one per line.
bins_of() {
	for f in "$cache/$plugin_name-$(name_of "$1")-"*; do
		h=${f##*-}
		[ "${#h}" -eq 64 ] && [ -f "$f" ] && case $h in *[!0-9a-f]*) ;; *) echo "$f" ;; esac
	done
}
# The binary the launcher would run for a hook now (empty if not built).
bin_of() {
	b=$(cd "${2:-$plugin}" && RUST_HOOK_WHICH=1 sh "./$1" </dev/null 2>/dev/null)
	[ -f "$b" ] && echo "$b"
}

# Waits for a hook's background build to end. The launcher takes the lock
# before it answers, and the builder drops it when done (built or failed).
wait_build() {
	i=0
	while [ "$i" -lt 600 ]; do
		locks=
		for l in "$cache/$plugin_name-$(name_of "$1")-"*.lock; do [ -d "$l" ] && locks=1; done
		[ -z "$locks" ] && return 0
		sleep 0.2
		i=$((i + 1))
	done
	echo "FAIL timed out waiting for the build of $1"
	fails=$((fails + 1))
}

# --- 1. A real build with Bazel's rustc -----------------------------------
export RUST_HOOK_RUSTC="$real_rustc"
for h in $hooks; do
	run_hook "$h" '{}'
	check "$h: a cache miss answers at once with the fallback" "$out" "$(fallback_of "$h")"
	contains "$h: and says it is building" "$err" "building in the background"
	check "$h: and exits 0" "$status" "0"
	wait_build "$h"
	run_hook "$h" '{}'
	check "$h: once built, exits 0" "$status" "0"
	check "$h: once built, the launcher says nothing" "$err" ""
	case "$out" in
	"{"*"}") echo "ok   $h: once built, answers JSON" ;;
	*)
		echo "FAIL $h: once built, answers JSON: $out / $err"
		fails=$((fails + 1))
		;;
	esac
	[ -n "$(bin_of "$h")" ] && ok=0 || ok=1
	check "$h: its binary is cached under the sources' sha256" "$ok" "0"
done
[ -n "$(find "$cache" -maxdepth 0 -perm 700)" ] && ok=0 || ok=1
check "the cache folder is private (700)" "$ok" "0"

# --- 2. A stub rustc ----------------------------------------------------------
rm -rf "$cache"
stub="$tmp/stub-rustc"
cat >"$stub" <<'EOF'
#!/bin/sh
out=; prev=
for a; do [ "$prev" = "-o" ] && out=$a; prev=$a; done
echo "$out" >>"$STUB_LOG"
echo "stub rustc says hello" >&2
[ -z "${STUB_FAIL:-}" ] || { echo "error: planted failure" >&2; exit 1; }
sleep "${STUB_SLEEP:-0}"
case " $* " in
*" rlib "*) : >"$out" ;;
*) printf '#!/bin/sh\nprintf stub-hook:\ncat\n' >"$out"; chmod +x "$out" ;;
esac
EOF
chmod +x "$stub"
export RUST_HOOK_RUSTC="$stub"
export STUB_LOG="$tmp/stub.log"
calls() { wc -l <"$STUB_LOG" | tr -d ' '; }
: >"$STUB_LOG"
log="$cache/$plugin_name-$(name_of "$first").log"

# The host kills the hook's whole process group at its timeout: the build
# must be in a group of its own and survive that.
export STUB_SLEEP=1
set -m
(cd "$plugin" && printf '{}' | sh -c "./$first" >"$tmp/out" 2>"$tmp/err") &
hook_pid=$!
set +m
wait "$hook_pid"
check "a cache miss answers with the fallback" "$(cat "$tmp/out")" "$(fallback_of "$first")"
# The stub takes 2 s (two calls of 1 s), so a binary now means the hook
# waited for the build: it must answer first (aegis's check).
[ -z "$(bin_of "$first")" ] && ok=0 || ok=1
check "a cache miss answers before the build finishes" "$ok" "0"
kill -KILL -- "-$hook_pid" 2>/dev/null
wait_build "$first"
unset STUB_SLEEP
[ -n "$(bin_of "$first")" ] && ok=0 || ok=1
check "the build survives the host killing the hook's process group" "$ok" "0"
contains "rustc's output goes to the log" "$(cat "$log")" "stub rustc says hello"
case "$(cat "$STUB_LOG")" in
*/.build.*/hook*) echo "ok   the hook is built in a private folder, then renamed" ;;
*)
	echo "FAIL the hook is built in a private folder, then renamed: $(cat "$STUB_LOG")"
	fails=$((fails + 1))
	;;
esac
check "a build is two rustc calls (library, then hook)" "$(calls)" "2"

run_hook "$first" '{"x":1}'
check "the built hook gets the payload on stdin" "$out" 'stub-hook:{"x":1}'
run_hook "$first" "$(printf '{"x":2}\n\n')"
check "trailing newlines reach the hook" "$(od -c <"$tmp/out" | tr -s ' ' | head -n 1)" "$(printf 'stub-hook:{"x":2}\n\n' | od -c | tr -s ' ' | head -n 1)"
check "a second run reuses the binary" "$(calls)" "2"

rebuilds_after() { # rebuilds_after <what> <command>
	before=$(bin_of "$first")
	eval "$2"
	run_hook "$first" '{}'
	wait_build "$first"
	after=$(bin_of "$first")
	[ -n "$after" ] && [ "$after" != "$before" ] && ok=0 || ok=1
	check "$1 rebuilds" "$ok" "0"
	[ -e "$before" ] && ok=0 || ok=1
	check "$1 keeps the old binary (another copy may use it)" "$ok" "0"
}
# shellcheck disable=SC2016 # expanded by eval in rebuilds_after
rebuilds_after "editing src/lib.rs" 'echo "// edited" >>"$plugin/hooks/src/lib.rs"'
mkdir -p "$plugin/hooks/src/bin"
# shellcheck disable=SC2016
rebuilds_after "adding a file under src/bin" 'echo "// new" >"$plugin/hooks/src/bin/zz_extra.rs"'
# shellcheck disable=SC2016
rebuilds_after "editing the launcher" 'echo "# edited" >>"$plugin/hooks/rust-hook.sh"'

# Two copies of the plugin (installed and development) with different
# sources share the cache: switching between them must not rebuild.
dev="$tmp/dev/$plugin_name"
rm -rf "${tmp:?}/dev"
mkdir -p "$tmp/dev"
cp -R "$plugin" "$dev"
echo "// the development copy" >>"$dev/hooks/src/lib.rs"
printf '{}' | (cd "$dev" && sh -c "./$first") >/dev/null 2>&1
wait_build "$first"
: >"$STUB_LOG"
for _ in 1 2 3; do
	run_hook "$first" '{}'
	check "switching copies: the installed copy answers" "$out" "stub-hook:{}"
	printf '{}' | (cd "$dev" && sh -c "./$first") >"$tmp/out" 2>/dev/null
	check "switching copies: the development copy answers" "$(cat "$tmp/out")" "stub-hook:{}"
done
check "switching copies rebuilds nothing" "$(calls)" "0"

# Binaries unused for RUST_HOOK_GC_DAYS days are collected by the next build;
# running one marks it used. Age them all, then use the current one.
current=$(bin_of "$first")
for f in $(bins_of "$first"); do
	touch -t 202001010000 "$f"
done
run_hook "$first" '{}'
check "(the current binary answers)" "$out" "stub-hook:{}"
old_count=$(bins_of "$first" | wc -l | tr -d ' ')
# shellcheck disable=SC2016
rebuilds_after "editing src/lib.rs once more" 'echo "// edited for gc" >>"$plugin/hooks/src/lib.rs"'
check "binaries unused for a week are removed, used ones kept" \
	"$(bins_of "$first" | wc -l | tr -d ' ')" "2"
[ -f "$current" ] && ok=0 || ok=1
check "a binary run this week is kept, however old the file" "$ok" "0"
[ "$old_count" -gt 1 ] && ok=0 || ok=1
check "(there were old binaries to collect)" "$ok" "0"

# --- 3. A broken cached binary -----------------------------------------------
b=$(bin_of "$first")
printf 'garbage' >"$b"
chmod +x "$b"
run_hook "$first" '{}'
check "a garbage binary: exits 0" "$status" "0"
check "a garbage binary: answers with the fallback" "$out" "$(fallback_of "$first")"
wait_build "$first"
[ "$(cat "$b" 2>/dev/null)" = garbage ] && ok=1 || ok=0
check "a garbage binary is replaced" "$ok" "0"
run_hook "$first" '{}'
check "a removed binary is rebuilt" "$out" "stub-hook:{}"

b=$(bin_of "$first")
printf '#!/bin/sh\nexit 3\n' >"$b"
run_hook "$first" '{}'
check "a binary that dies without answering: fallback" "$out" "$(fallback_of "$first")"
wait_build "$first"

# Exit 0 with no answer is not a verdict either (on PreToolUse it would
# let the call through).
b=$(bin_of "$first")
printf '#!/bin/sh\nexit 0\n' >"$b"
run_hook "$first" '{}'
check "a binary that exits 0 without answering: fallback" "$out" "$(fallback_of "$first")"
check "a binary that exits 0 without answering: exit 0" "$status" "0"
wait_build "$first"
run_hook "$first" '{}'
check "and it is rebuilt" "$out" "stub-hook:{}"

rm -f "$(bin_of "$first")"
run_hook "$first" '{}'
check "a deleted binary: answers with the fallback" "$out" "$(fallback_of "$first")"
check "a deleted binary: exits 0" "$status" "0"
wait_build "$first"
run_hook "$first" '{}'
check "a deleted binary is rebuilt" "$out" "stub-hook:{}"

# --- 3b. Locks ------------------------------------------------------------
echo "// lock tests" >>"$plugin/hooks/src/lib.rs"
export STUB_SLEEP=30
run_hook "$first" '{}'
lock=$(find "$cache" -maxdepth 1 -type d -name "$plugin_name-$(name_of "$first")-*.lock" | head -n 1)
[ -n "$lock" ] && [ -f "$lock/pid" ] && ok=0 || ok=1
check "the lock records its builder" "$ok" "0"
run_hook "$first" '{}'
contains "a live builder's lock is respected" "$err" "being built in the background"
echo $(($(date +%s) - 600)) >"$lock/since"
run_hook "$first" '{}'
contains "a live builder's lock is respected 10 minutes in" "$err" "being built in the background"
echo $(($(date +%s) - 3600)) >"$lock/since"
cp -R "$lock" "$tmp/lock.saved"
run_hook "$first" '{}'
contains "a live builder's lock over 30 minutes old is taken over" "$err" "building in the background (first run"
# The builder that lost its lock must not delete its successor's when it
# finishes: rerun the takeover with a first builder that ends soon.
i=0
while [ ! -f "$lock/pid" ] && [ "$i" -lt 50 ]; do
	sleep 0.1
	i=$((i + 1))
done
second=$(cat "$lock/pid")
kill -KILL "$second" 2>/dev/null
kill -KILL -- "-$second" 2>/dev/null
rm -rf "$lock"
echo "// lock tests: successor" >>"$plugin/hooks/src/lib.rs"
export STUB_SLEEP=2
run_hook "$first" '{}'
lock=$(find "$cache" -maxdepth 1 -type d -name "$plugin_name-$(name_of "$first")-*.lock" | head -n 1)
i=0
while [ ! -f "$lock/pid" ] && [ "$i" -lt 50 ]; do
	sleep 0.1
	i=$((i + 1))
done
early=$(cat "$lock/pid")
echo $(($(date +%s) - 3600)) >"$lock/since"
export STUB_SLEEP=30
run_hook "$first" '{}'
contains "(a 30-minute-old lock is taken over)" "$err" "building in the background (first run"
i=0
while kill -0 "$early" 2>/dev/null && [ "$i" -lt 150 ]; do
	sleep 0.1
	i=$((i + 1))
done
kill -0 "$early" 2>/dev/null && ok=1 || ok=0
check "(the replaced builder finished)" "$ok" "0"
[ -d "$lock" ] && [ "$(cat "$lock/pid" 2>/dev/null)" != "$early" ] && ok=0 || ok=1
check "a replaced builder leaves its successor's lock alone" "$ok" "0"
# The replaced builder finished a binary; drop it so the cases below miss.
rm -f "$(bin_of "$first")"
export STUB_SLEEP=30

# Stop the builder that took over, and put the first builder's lock back for
# the dead-builder case below.
i=0
while [ ! -f "$lock/pid" ] && [ "$i" -lt 50 ]; do
	sleep 0.1
	i=$((i + 1))
done
second=$(cat "$lock/pid")
kill -KILL "$second" 2>/dev/null
kill -KILL -- "-$second" 2>/dev/null
rm -rf "$lock"
cp -R "$tmp/lock.saved" "$lock"
date +%s >"$lock/since"
# The builder dies without cleaning up (as on SIGKILL): its lock is stale.
builder=$(cat "$lock/pid")
# Kill the builder first (a builder that outlives its rustc records a
# failed build), then the rest of its process group: it leads its own
# session, so its pid is the group.
kill -KILL "$builder" 2>/dev/null
kill -KILL -- "-$builder" 2>/dev/null
sleep 0.3
[ -d "$lock" ] && ok=0 || ok=1
check "(a killed builder leaves its lock behind)" "$ok" "0"
unset STUB_SLEEP
run_hook "$first" '{}'
contains "a dead builder's lock is taken over" "$err" "building in the background (first run"
wait_build "$first"
# A hook killed between taking the lock and starting the builder leaves a
# lock with no builder: taken over once a few seconds old.
echo "// lock tests 2" >>"$plugin/hooks/src/lib.rs"
export STUB_SLEEP=30
run_hook "$first" '{}'
lock=$(find "$cache" -maxdepth 1 -type d -name "$plugin_name-$(name_of "$first")-*.lock" | head -n 1)
builder=$(cat "$lock/pid")
# Kill the builder first (a builder that outlives its rustc records a
# failed build), then the rest of its process group: it leads its own
# session, so its pid is the group.
kill -KILL "$builder" 2>/dev/null
kill -KILL -- "-$builder" 2>/dev/null
unset STUB_SLEEP
rm -f "$lock/pid" "$lock/detached"
date +%s >"$lock/since"
run_hook "$first" '{}'
contains "a just-taken lock with no builder yet is respected" "$err" "being built in the background"
echo $(($(date +%s) - 10)) >"$lock/since"
run_hook "$first" '{}'
contains "an orphaned lock is taken over after a few seconds" "$err" "building in the background (first run"
wait_build "$first"
run_hook "$first" '{}'
check "and the hook then builds and runs" "$out" "stub-hook:{}"
# The builders killed above left their build folders: the next build
# removes those over an hour old.
for d in "$cache"/.build.*; do [ -d "$d" ] && touch -t 202001010000 "$d"; done
echo "// lock tests 3" >>"$plugin/hooks/src/lib.rs"
run_hook "$first" '{}'
wait_build "$first"
leftover=no
for f in "$cache"/.build.*; do [ -e "$f" ] && leftover=yes; done
check "build folders of killed builds are cleaned up" "$leftover" "no"

# --- 4. A build that fails ------------------------------------------------------
echo "// edited again" >>"$plugin/hooks/src/lib.rs"
export STUB_FAIL=1
for h in $hooks; do
	rm -f "$cache/$plugin_name-$(name_of "$h")-"*.failed
	run_hook "$h" '{}'
	wait_build "$h"
	: >"$STUB_LOG"
	run_hook "$h" '{}'
	check "$h: a failed build exits 0" "$status" "0"
	check "$h: a failed build answers with the fallback" "$out" "$(fallback_of "$h")"
	contains "$h: a failed build says so" "$err" "the last build failed"
	check "$h: a failed build is not retried at once" "$(calls)" "0"
	contains "$h: the log has rustc's error" "$(cat "$cache/$plugin_name-$(name_of "$h").log")" "planted failure"
done
unset STUB_FAIL
run_hook "$first" '{}'
contains "within the back-off a failed build stays failed, even if rustc works now" "$err" "the last build failed"
for f in "$cache"/*.failed; do touch -t 202001010000 "$f"; done
run_hook "$first" '{}'
wait_build "$first"
run_hook "$first" '{}'
check "after the back-off, a failed build is retried and recovers" "$out" "stub-hook:{}"
leftover=no
for f in "$cache"/.build.*; do [ -e "$f" ] && leftover=yes; done
check "no build folders are left behind" "$leftover" "no"

# --- 5. No rustc ------------------------------------------------------------------
echo "// and again" >>"$plugin/hooks/src/lib.rs"
export RUST_HOOK_RUSTC="$tmp/no-such-rustc"
for h in $hooks; do
	run_hook "$h" '{}'
	check "$h without rustc exits 0" "$status" "0"
	check "$h without rustc answers with the fallback" "$out" "$(fallback_of "$h")"
	contains "$h without rustc says so" "$err" "rustc not found"
done

# --- 6. An unsafe cache folder -------------------------------------------------
export RUST_HOOK_RUSTC="$stub"
chmod 777 "$cache"
run_hook "$first" '{}'
check "a world-writable cache: fallback" "$out" "$(fallback_of "$first")"
contains "a world-writable cache: refused" "$err" "refusing"
chmod 770 "$cache"
run_hook "$first" '{}'
check "a group-writable cache: fallback" "$out" "$(fallback_of "$first")"
contains "a group-writable cache: refused" "$err" "refusing"
chmod 700 "$cache"
mv "$cache" "$cache.real"
ln -s "$cache.real" "$cache"
run_hook "$first" '{}'
check "a symlinked cache: fallback" "$out" "$(fallback_of "$first")"
contains "a symlinked cache: refused" "$err" "refusing"
rm "$cache"
mv "$cache.real" "$cache"

if [ "$fails" -ne 0 ]; then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
