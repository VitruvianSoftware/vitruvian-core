// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use gchat_ffi::fuzz_tests::{fuzz_pblite_event_once, Xorshift64};

#[test]
fn fuzz_pblite_event_never_panics_on_deep_and_malformed_json() {
    let deep_open = "[".repeat(256);
    let deep_close = "]".repeat(256);
    let deep = format!("{deep_open}1{deep_close}");
    let seeds: Vec<&[u8]> = vec![
        b"",
        b")]}'\n[[1,[null,null,1710000000000]]]",
        b"[[[null,[[1,[null,null,null,null,[[null,null,null,[[[null,\"space/AAA\",\"t1\",\"m1\"]]],null,null,null,null,\"Hello\"]]]]]]]]",
        b"[null,1,-99999999999999999999999999,\"NaN\",\"Infinity\",\"-Infinity\",{\"15\":{\"1\":\"x\"}}]",
        b"{\"1\": \"hello\", \"15\": {\"1\": 42}}",
        deep.as_bytes(),
    ];
    for seed in seeds {
        assert!(
            fuzz_pblite_event_once(seed),
            "fuzz_pblite_event_once failed on seed {:?}",
            seed
        );
    }

    let mut rng = Xorshift64::new(0xDEAD_C0DE_8765_4321);
    for _ in 0..500 {
        let buf = rng.next_bytes(512);
        assert!(fuzz_pblite_event_once(&buf));
    }
}
