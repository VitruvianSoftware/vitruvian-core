#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Runs the real Space arrangement check from Tools/uninstall.sh, lifted out of
# the script so nothing here quits, resets or removes anything.
set -euo pipefail
cd "$(dirname "$0")/.."
source <(sed -n '/^spaces_leftover() {$/,/^}$/p' Tools/uninstall.sh)
(( $+functions[spaces_leftover] ))

failures=0
expect() {
    local wanted=$1 owed=$2 dock_runs=$3 preference=$4 found
    found="$(spaces_leftover "$owed" "$dock_runs" "$preference")"
    if [[ "$found" != "$wanted" ]]; then
        print -u2 "spaces_leftover '$owed' '$dock_runs' '$preference': wanted '$wanted', found '$found'"
        failures=$((failures + 1))
    fi
}

# Settled: nothing owed, or a restore the Dock already reads.
expect "" "" "" ""
expect "" "" "" "1"
expect "" "absent" "" ""
expect "" "on" "" "1"
# Rearranging the user turned off themselves is theirs, not a failed restore.
expect "" "" "" "0"
# A restore that never happened.
expect stuck "absent" "" "0"
expect stuck "on" "rearranging" "0"
# A restore written back while the Dock still keeps a fixed order.
expect unloaded "absent" "fixed" ""
expect unloaded "on" "fixed" "1"
# The marker can already be gone while the restart is still owed.
expect unloaded "" "fixed" ""
expect unloaded "" "fixed" "1"
# The Dock already runs what an owed restart would load.
expect "" "" "fixed" "0"
expect "" "" "rearranging" "1"

(( failures == 0 )) || exit 1
print 'UNINSTALL SPACES TESTS OK'
