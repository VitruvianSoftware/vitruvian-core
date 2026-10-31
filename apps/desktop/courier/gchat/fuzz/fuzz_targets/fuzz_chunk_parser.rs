// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use gchat_ffi::fuzz_tests::{fuzz_chunk_parser_once, Xorshift64};

#[test]
fn fuzz_chunk_parser_never_panics_on_adversarial_and_random_inputs() {
    let seeds: &[&[u8]] = &[
        b"",
        b"\n",
        b"0\n",
        b"14\n[[1,[\"noop\"]]]",
        b"29\n[[2,[null,null,null,[[[1]]]]]]",
        b"999999999999999999999999999999\n[]",
        b"-1\n[]",
        b"5\n\xF0\x9F\x91\x8B!",
        b"3\n\xF0\x9F\x91\x8B!",
        b"12\n[[1,[\"noop\"]]]4\n[[]]",
    ];
    for seed in seeds {
        assert!(
            fuzz_chunk_parser_once(seed),
            "fuzz_chunk_parser_once failed on seed {:?}",
            seed
        );
    }

    let mut rng = Xorshift64::new(0xC001_BEEF_1234_5678);
    for _ in 0..500 {
        let buf = rng.next_bytes(512);
        assert!(fuzz_chunk_parser_once(&buf));
    }
}
