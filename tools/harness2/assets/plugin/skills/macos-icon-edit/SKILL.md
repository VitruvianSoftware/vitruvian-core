---
name: macos-icon-edit
description: Measure, crop, strip a border from, scale and pad an EXISTING icon or image deterministically (standard-library Python plus sips), including fitting artwork to the macOS 1024/824 icon grid.
---

# Editing an existing icon's pixels

An edit of an existing image is arithmetic on its pixels, not a request for new art. Never use
an image generator for it: a hook refuses one on these requests anyway.

Script: `~/.gemini/config/plugins/harness2/skills/macos-icon-edit/scripts/icon_crop_scale.py`
(helper at `scripts/icon_crop_scale.py` in this skill; Python standard library and `sips` only).

1. Confirm the target. Name the file you will change and the files you will not. If the user
   locked a file, do not write it, not even to "restore" it.
2. Measure first:
   `python3 <script> inspect IN.png` prints the canvas, the content box, its margins, and
   whether it is on the macOS grid (1024 canvas, 824 artwork, 100 margin).
3. Transform into a NEW file, never over the input:
   `python3 <script> crop-scale IN.png /tmp/out.png --strip-color FFFFFF`
   strips a white border (`--strip-color` takes any RRGGBB; transparent pixels are always
   border), makes it transparent, scales the artwork to 824 and centres it on 1024.
   `--content N --canvas M` for other sizes; `--no-square` keeps the box's aspect ratio;
   lower `--tolerance` (default 12) if it eats into a light edge of the artwork.
4. Check the result: run `inspect` on the output (expect `macos_grid: true` for an app icon)
   and look at it before you copy it over the target.
5. Report the numbers: input box, output canvas, artwork size. When the user asked for a
   resolution, quote it back.

For an app icon the artwork is 824x824 on a 1024x1024 canvas. "Enlarge to replace the border"
means scale the artwork up to 824, not to 1024.
