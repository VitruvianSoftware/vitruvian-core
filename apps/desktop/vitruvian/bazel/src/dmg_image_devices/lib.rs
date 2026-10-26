// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::collections::HashSet;

pub fn extract_devices(hdiutil_info: &str, target: &str) -> Vec<String> {
    let stripped = target.strip_prefix("/private").unwrap_or(target);
    let private_prefixed = format!("/private{}", target);
    let mut matched = false;
    let mut seen = HashSet::new();
    let mut devices = Vec::new();

    for line in hdiutil_info.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("===") {
            matched = false;
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("image-path") {
            let rest_trimmed = rest.trim_start();
            if let Some(after_colon) = rest_trimmed.strip_prefix(':') {
                let path = after_colon.trim();
                matched = path == target || path == private_prefixed || path == stripped;
                continue;
            }
        }
        if matched {
            if let Some(dev) = extract_whole_disk(trimmed) {
                if seen.insert(dev.clone()) {
                    devices.push(dev);
                }
            }
        }
    }
    devices
}

fn extract_whole_disk(trimmed_line: &str) -> Option<String> {
    let rest = trimmed_line.strip_prefix("/dev/disk")?;
    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    if digits.is_empty() {
        return None;
    }
    Some(format!("/dev/disk{}", digits))
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = "\
framework       : 668.100.18
driver          : 668.100.18
================================================
image-path      : /private/var/folders/xx/T/tmp.other/rw.dmg
image-alias     : /private/var/folders/xx/T/tmp.other/rw.dmg
shadow-path     : <none>
icon-path       : /System/Library/PrivateFrameworks/DiskImages.framework/Resources/CDiskImage.icns
image-type      : read/write disk image
system-image    : false
blockcount      : 163840
blocksize       : 512
writeable       : TRUE
autodiskmount   : TRUE
removable       : TRUE
image-encrypted : false
mounting user   : runner
mounting mode   : <unknown>
process ID      : 41001
/dev/disk5          \tGUID_partition_scheme          \t
/dev/disk5s1        \t48465300-0000-11AA-AA11-00306543ECAC\t/Volumes/Vitruvian
================================================
image-path      : /private/var/folders/xx/T/tmp.build/rw.dmg
image-alias     : /private/var/folders/xx/T/tmp.build/rw.dmg
shadow-path     : <none>
icon-path       : /System/Library/PrivateFrameworks/DiskImages.framework/Resources/CDiskImage.icns
image-type      : read/write disk image
system-image    : false
blockcount      : 163840
blocksize       : 512
writeable       : TRUE
autodiskmount   : TRUE
removable       : TRUE
image-encrypted : false
mounting user   : runner
mounting mode   : <unknown>
process ID      : 41203
/dev/disk7          \tFDisk_partition_scheme         \t
/dev/disk7s1        \tApple_HFS                      \t
================================================
image-path      : /private/var/folders/xx/T/tmp.multi/rw.dmg
/dev/disk12         \tGUID_partition_scheme          \t
/dev/disk12s1       \tEFI                            \t
/dev/disk12s2       \tApple_HFS                      \t/Volumes/Vitruvian 1
================================================
image-path      : /var/folders/xx/T/tmp.multi/rw.dmg
/dev/disk14         \tApple_HFS                      \t
";

    #[test]
    fn test_unmounted_attachment_with_no_mount_point() {
        let got = extract_devices(FIXTURE, "/var/folders/xx/T/tmp.build/rw.dmg");
        assert_eq!(got, vec!["/dev/disk7"]);
    }

    #[test]
    fn test_multiple_slices_and_second_attachment() {
        let got = extract_devices(FIXTURE, "/var/folders/xx/T/tmp.multi/rw.dmg");
        assert_eq!(got, vec!["/dev/disk12", "/dev/disk14"]);
    }

    #[test]
    fn test_private_prefixed_argument() {
        let got = extract_devices(FIXTURE, "/private/var/folders/xx/T/tmp.build/rw.dmg");
        assert_eq!(got, vec!["/dev/disk7"]);
    }

    #[test]
    fn test_image_not_present() {
        let got = extract_devices(FIXTURE, "/var/folders/xx/T/tmp.absent/rw.dmg");
        assert!(got.is_empty());
    }
}
