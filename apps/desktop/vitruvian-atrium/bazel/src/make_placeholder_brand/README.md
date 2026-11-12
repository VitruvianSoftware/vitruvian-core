# Make Placeholder Brand

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/bazel/src/make_placeholder_brand`.

## Interface
- `[lib.rs:SIZE]`
- `[lib.rs:RADIUS]`
- `[lib.rs:STROKE]`
- `[lib.rs:CENTER]`
- `[lib.rs:SIDE]`
- `[lib.rs:BOTTOM]`
- `[lib.rs:SQUARE_CENTER]`
- `[lib.rs:clamp]`
- `[lib.rs:box_sdf]`
- `[lib.rs:mark_distance]`
- `[lib.rs:crc32_ieee]`
- `[lib.rs:zlib_compress_level9]`
- `[lib.rs:encode_png]`
- `[lib.rs:write_png]`
- `[lib.rs:round_half_to_even]`
- `[lib.rs:render_logo_with_size]`
- `[lib.rs:render_logo]`
- `[lib.rs:render_icon_with_size]`
- `[lib.rs:render_icon]`
- `[lib.rs:mark_svg]`

## Invariants
- [lib.rs:397]: `assert!((d_ring - (-32.0)).abs() < 1e-9);`
- [lib.rs:402]: `assert!(png.starts_with(b"\x89PNG\r\n\x1a\n"));`
- [lib.rs:403]: `assert!(png.ends_with(b"IEND\xae\x42\x60\x82"));`

## Side Effects
- [lib.rs:237]: `<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{le...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/bazel/src/make_placeholder_brand/...`
