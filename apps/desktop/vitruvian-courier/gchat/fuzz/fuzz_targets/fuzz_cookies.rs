// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use gchat_ffi::fuzz_tests::{fuzz_cookies_once, Xorshift64};

#[test]
fn fuzz_cookies_never_panics_on_arbitrary_headers_and_maps() {
    let seeds: &[&[u8]] = &[
        b"",
        b"COMPASS=dynamite=c1; Path=/; Secure; HttpOnly\nOSID=o1; Domain=chat.google.com; Secure\nSID=s1; Domain=.google.com\nHSID=h1; Domain=.google.com\nSSID=ss1; Domain=.google.com",
        b"SID=; Max-Age=0\nOSID=expired; Expires=Thu, 01 Jan 1970 00:00:00 GMT",
        b"===; ; ; Max-Age=-999999999999999999999999999",
    ];
    for seed in seeds {
        assert!(
            fuzz_cookies_once(seed),
            "fuzz_cookies_once failed on seed {:?}",
            seed
        );
    }

    let mut rng = Xorshift64::new(0xABCD_EF01_2345_6789);
    for _ in 0..500 {
        let buf = rng.next_bytes(256);
        assert!(fuzz_cookies_once(&buf));
    }
}
