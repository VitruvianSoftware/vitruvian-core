// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::collections::HashSet;

/// The whole-disk device (`/dev/diskN`) of every attachment of the disk image
/// at `target`, read from `hdiutil info` output, as
/// `Tools/dmg-image-devices.sh` printed them: a section (between `====` lines)
/// is the image's when its `image-path` or `image-alias` is the image, and a
/// device line of that section names a whole disk. A path under `/private`
/// and the same path without it are one image (`/var` is `/private/var`).
pub fn extract_devices(hdiutil_info: &str, target: &str) -> Vec<String> {
    let bare = target.strip_prefix("/private").unwrap_or(target);
    let same_image =
        |path: &str| path == target || path.strip_prefix("/private").unwrap_or(path) == bare;
    let mut mine = false;
    let mut seen = HashSet::new();
    let mut devices = Vec::new();

    for line in hdiutil_info.lines() {
        if !line.is_empty() && line.bytes().all(|b| b == b'=') {
            mine = false;
            continue;
        }
        if let Some(path) = attribute(line, "image-path").or_else(|| attribute(line, "image-alias"))
        {
            if same_image(path) {
                mine = true;
            }
            continue;
        }
        if mine {
            if let Some(dev) = whole_disk(line) {
                if seen.insert(dev.clone()) {
                    devices.push(dev);
                }
            }
        }
    }
    devices
}

/// The value of `name   : value`, for a line that starts with `name`.
fn attribute<'a>(line: &'a str, name: &str) -> Option<&'a str> {
    let rest = line.strip_prefix(name)?;
    let rest = rest.trim_start_matches([' ', '\t']);
    let value = rest.strip_prefix(':')?;
    Some(value.trim_start_matches([' ', '\t']))
}

/// `/dev/diskN` for a line that starts with exactly that device followed by
/// a blank (a slice such as `/dev/disk7s1` is not a whole disk).
fn whole_disk(line: &str) -> Option<String> {
    let rest = line.strip_prefix("/dev/disk")?;
    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    if digits.is_empty() {
        return None;
    }
    match rest[digits.len()..].chars().next() {
        Some(' ') | Some('\t') => Some(format!("/dev/disk{}", digits)),
        _ => None,
    }
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
    fn test_alias_alone_names_the_image() {
        let info = "================\nimage-path      : /Volumes/x/link.dmg\nimage-alias     : /tmp/w/rw-2.dmg\n/dev/disk20\tGUID_partition_scheme\t\n/dev/disk20s1\tApple_HFS\t\n";
        assert_eq!(
            extract_devices(info, "/tmp/w/rw-2.dmg"),
            vec!["/dev/disk20"]
        );
    }

    #[test]
    fn test_slices_alone_are_not_whole_disks() {
        let info =
            "================\nimage-path      : /tmp/w/rw-1.dmg\n/dev/disk21s1\tApple_HFS\t\n";
        assert!(extract_devices(info, "/tmp/w/rw-1.dmg").is_empty());
    }

    /// The `hdiutil info` a macOS runner printed when a failed create left
    /// its image attached with no mount point (bazel/testdata).
    #[test]
    fn test_runner_capture_finds_the_stale_image() {
        let path = std::env::var("HDIUTIL_INFO_FIXTURE").expect("HDIUTIL_INFO_FIXTURE");
        let info = std::fs::read_to_string(path).unwrap();
        assert_eq!(
            extract_devices(
                &info,
                "/var/folders/5n/5t77mfb93jd7q8v9s6f0dn0m0000gn/T/tmp.CoP6rzGdbe/rw.dmg"
            ),
            vec!["/dev/disk13"]
        );
        assert_eq!(
            extract_devices(
                &info,
                "/System/Library/AssetsV2/com_apple_MobileAsset_PKITrustStore/purpose_auto/6dd55b0d06633a00de6f57ccb910a66a5ba2409a.asset/AssetData/Restore/SECUREPKITRUSTSTOREASSETS_SECUREPKITRUSTSTORE_Cryptex.dmg"
            ),
            vec!["/dev/disk3", "/dev/disk4"]
        );
    }

    #[test]
    fn test_image_not_present() {
        let got = extract_devices(FIXTURE, "/var/folders/xx/T/tmp.absent/rw.dmg");
        assert!(got.is_empty());
    }
}
