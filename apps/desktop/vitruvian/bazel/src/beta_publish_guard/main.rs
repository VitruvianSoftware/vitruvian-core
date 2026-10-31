// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! `bazel run //apps/desktop/vitruvian:beta_publish_guard -- <status>`
//! prints `publish`, `skip` or `refuse`. publish calls the library directly.

fn main() {
    let status = std::env::args().nth(1).unwrap_or_default();
    println!("{}", beta_publish_guard::decide(&status).word());
}
