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


# Run //tools/agent-plugins:refresh on a schedule, so a merged plugin change
# reaches Claude Code, Antigravity and OpenCode on this Mac without anyone
# asking for it.
#
#   bazel run //tools/agent-plugins:schedule -- install [--every <minutes>]
#   bazel run //tools/agent-plugins:schedule -- status
#   bazel run //tools/agent-plugins:schedule -- remove
#
# `install` writes a launchd agent that runs the main checkout's refresh.sh
# --quiet every 30 minutes (and once at login). The job runs the script from the
# main checkout, which refresh itself fast-forwards, so the job always runs the
# newest refresh. --quiet logs only runs that changed something, are stale or
# failed, to ~/Library/Logs/vitruvian/agent-plugins-refresh.log.

set -euo pipefail

LABEL="dev.vitruvian.agent-plugins-refresh"
AGENTS_DIR="${AGENT_PLUGINS_LAUNCH_AGENTS:-$HOME/Library/LaunchAgents}"
LOG_DIR="${AGENT_PLUGINS_LOG_DIR:-$HOME/Library/Logs/vitruvian}"
LAUNCHCTL="${AGENT_PLUGINS_LAUNCHCTL:-launchctl}"
PLIST="$AGENTS_DIR/$LABEL.plist"
LOG="$LOG_DIR/agent-plugins-refresh.log"
DOMAIN="gui/$(id -u)"

usage() {
  sed -n '/^# Run \/\/tools\/agent-plugins:refresh/,/^# failed, to/p' "$0" | sed 's/^# \{0,1\}//'
}

if [[ -n "${AGENT_PLUGINS_MAIN_CHECKOUT:-}" ]]; then
  MAIN="$AGENT_PLUGINS_MAIN_CHECKOUT"
else
  ws="${BUILD_WORKSPACE_DIRECTORY:-$PWD}"
  MAIN="$(dirname "$(git -C "$ws" rev-parse --path-format=absolute --git-common-dir)")"
fi
REFRESH="$MAIN/tools/agent-plugins/refresh.sh"

xml() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$1"; }

cmd="${1:-}"
[[ $# -gt 0 ]] && shift
case "$cmd" in
  install)
    every=30
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --every)
          [[ $# -ge 2 && "$2" =~ ^[0-9]+$ && "$2" -ge 5 ]] || { echo "--every needs a whole number of minutes, 5 or more" >&2; exit 2; }
          every="$2"
          shift
          ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
      esac
      shift
    done
    [[ "${AGENT_PLUGINS_UNAME:-$(uname -s)}" == "Darwin" ]] || { echo "schedule uses launchd, so it only runs on macOS" >&2; exit 2; }
    [[ -f "$REFRESH" ]] || { echo "no $REFRESH in the main checkout; update it first (bazel run //tools/git:update-main)" >&2; exit 1; }
    grep -q -- '--quiet' "$REFRESH" || { echo "the main checkout's refresh.sh has no --quiet yet; update it first (bazel run //tools/git:update-main)" >&2; exit 1; }
    mkdir -p "$AGENTS_DIR" "$LOG_DIR"
    # A login shell, so the job finds claude, agy, git and python3 on the same PATH as a terminal.
    cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>exec /bin/bash "\$0" --quiet</string>
    <string>$(xml "$REFRESH")</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>AGENT_PLUGINS_MAIN_CHECKOUT</key>
    <string>$(xml "$MAIN")</string>
  </dict>
  <key>StartInterval</key>
  <integer>$((every * 60))</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>$(xml "$LOG")</string>
  <key>StandardErrorPath</key>
  <string>$(xml "$LOG")</string>
</dict>
</plist>
PLIST
    "$LAUNCHCTL" bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    "$LAUNCHCTL" bootstrap "$DOMAIN" "$PLIST"
    echo "Installed $LABEL: refreshes agent plugins every $every minutes and at login."
    echo "  job:  $PLIST"
    echo "  log:  $LOG (only runs that changed something or failed)"
    ;;
  remove)
    "$LAUNCHCTL" bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    if [[ -f "$PLIST" ]]; then rm -f "$PLIST"; echo "Removed $LABEL."; else echo "$LABEL was not installed."; fi
    ;;
  status)
    if [[ ! -f "$PLIST" ]]; then echo "$LABEL is not installed. Run: bazel run //tools/agent-plugins:schedule -- install"; exit 1; fi
    if "$LAUNCHCTL" print "$DOMAIN/$LABEL" >/dev/null 2>&1; then echo "$LABEL is installed and loaded ($PLIST)."; else echo "$LABEL has a job file but is not loaded; run install again."; exit 1; fi
    if [[ -s "$LOG" ]]; then echo "Last logged run:"; tail -n 12 "$LOG" | sed 's/^/  /'; else echo "No run has changed anything yet (the log is empty)."; fi
    ;;
  -h | --help | "") usage; [[ -n "$cmd" ]] || exit 2 ;;
  *) echo "unknown command: $cmd (install, status or remove)" >&2; exit 2 ;;
esac
