# Replay

## Overview
Answers "does the presubmit planner wake fewer Mac units than it used to?" without
waiting for a week of traffic. It plans recent main commits (each one a squashed PR)
twice: with the dependency map as it is (the rule from #4815) and with the map's
`unit_packages` removed (the rule before it), then counts Mac unit wakes under each.

## Usage
```sh
# 1. fetch the map for a recent main commit (it must carry unit_packages)
git fetch origin main
bazel run --run_under="cd $PWD &&" //tools/ci:rdeps_map_ref -- fetch /tmp/map.json $(git rev-parse origin/main)
# 2. replay the last 300 commits
bazel run //tools/pipeline/replay -- --map /tmp/map.json --commits 300
```

## Invariants
- Live Bazel queries are refused: a commit whose plan needs one, or that touches
  everything, is counted as skipped, never guessed.
- The new rule is meant to be narrower. If it ever wakes a unit the old rule did not,
  the report says so.

## Limits
- Files are mapped to packages with the current checkout, so files added or moved
  since the commit are approximated (they usually show up as skipped).
- It counts wakes, not minutes: multiply by each unit's median job time to get minutes.

## Verification
- `bazel test //tools/pipeline/replay:replay_test`
