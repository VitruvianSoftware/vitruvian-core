# Scripts

## Overview
Component package providing implementation for `tools/harness2/assets/plugin/skills/macos-icon-edit/scripts`.

## Interface
- `[icon_crop_scale.py:Image]`
- `[icon_crop_scale.py:read_png]`
- `[icon_crop_scale.py:write_png]`
- `[icon_crop_scale.py:background_mask]`
- `[icon_crop_scale.py:content_box]`
- `[icon_crop_scale.py:strip_colours]`
- `[icon_crop_scale.py:measure]`
- `[icon_crop_scale.py:crop]`
- `[icon_crop_scale.py:square_box]`
- `[icon_crop_scale.py:resize_bilinear]`
- `[icon_crop_scale.py:resize]`
- `[icon_crop_scale.py:pad]`
- `[icon_crop_scale.py:main]`

## Invariants
- None

## Side Effects
- [icon_crop_scale.py:30]: `import subprocess`
- [icon_crop_scale.py:334]: `r = subprocess.run(`

## Verification
- Run: `bazel test //tools/harness2/assets/plugin/skills/macos-icon-edit/scripts/...`
