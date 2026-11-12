// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use std::env;
use std::path::PathBuf;

fn main() {
    let out_dir = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR must be set"));
    let manifest_dir =
        PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR must be set"));
    let descriptor_path = out_dir.join("googlechat_descriptor.bin");
    let proto_file = manifest_dir.join("proto/googlechat.proto");
    let proto_include = manifest_dir.join("proto");

    println!("cargo:rerun-if-changed=proto/googlechat.proto");

    let mut config = prost_build::Config::new();
    config.file_descriptor_set_path(&descriptor_path);

    prost_reflect_build::Builder::new()
        .descriptor_pool("crate::DESCRIPTOR_POOL")
        .file_descriptor_set_path(&descriptor_path)
        .configure(&mut config, &[&proto_file], &[&proto_include])
        .expect("prost_reflect_build::configure failed");

    config
        .compile_protos(&[&proto_file], &[&proto_include])
        .expect("prost_build::compile_protos failed");
}
