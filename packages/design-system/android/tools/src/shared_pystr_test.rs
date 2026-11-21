// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! This tool's argparse is the shared one (vitruvian-pycompat), which calls
//! the shared pystr. This checks, over every code point, that the four pystr
//! functions argparse uses answer exactly as this tool's own pystr does, so
//! its help and error output cannot drift from the rest of the tool.

#[test]
fn shared_pystr_matches_this_tools_own() {
    for cp in 0u32..=0x10FFFF {
        let Some(c) = char::from_u32(cp) else {
            continue;
        };
        assert_eq!(
            crate::pystr::is_space(c),
            vitruvian_pycompat::pystr::is_space(c),
            "is_space {cp:#x}"
        );
        assert_eq!(
            crate::pystr::decimal_value(c),
            vitruvian_pycompat::pystr::decimal_value(c),
            "decimal {cp:#x}"
        );
        let s = c.to_string();
        assert_eq!(
            crate::pystr::repr_str(&s),
            vitruvian_pycompat::pystr::repr_str(&s),
            "repr {cp:#x}"
        );
        let p = format!(" {c}x{c} ");
        assert_eq!(
            crate::pystr::strip(&p),
            vitruvian_pycompat::pystr::strip(&p),
            "strip {cp:#x}"
        );
    }
    for s in [
        "",
        "'",
        "\"",
        "'\"",
        "a'b",
        "\\",
        "\t\n\r",
        "\u{7f}\u{80}\u{ad}",
    ] {
        assert_eq!(
            crate::pystr::repr_str(s),
            vitruvian_pycompat::pystr::repr_str(s),
            "{s:?}"
        );
    }
}
