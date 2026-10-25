// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Which Macs a program runs on, read from its Mach-O header as bump.py
//! reads it: universal (fat) headers, 32- and 64-bit, and the oldest macOS
//! from LC_BUILD_VERSION or LC_VERSION_MIN_MACOSX.

pub const FAT_MAGIC: u32 = 0xCAFEBABE;
pub const FAT_MAGIC_64: u32 = 0xCAFEBABF;
pub const MH_MAGIC: u32 = 0xFEEDFACE;
pub const MH_MAGIC_64: u32 = 0xFEEDFACF;
const LC_VERSION_MIN_MACOSX: u32 = 0x24;
const LC_BUILD_VERSION: u32 = 0x32;
const PLATFORM_MACOS: u32 = 1;

/// (major, minor, patch).
pub type Version = (u32, u32, u32);

/// One architecture: its name and the oldest macOS it names, if any.
pub type Slice = (String, Option<Version>);

/// `version_text(version)`: 14.0, 15.4, 13.5.1.
pub fn version_text(v: Version) -> String {
    if v.2 != 0 {
        format!("{}.{}.{}", v.0, v.1, v.2)
    } else {
        format!("{}.{}", v.0, v.1)
    }
}

fn be32(d: &[u8], at: usize) -> u32 {
    u32::from_be_bytes([d[at], d[at + 1], d[at + 2], d[at + 3]])
}

fn be64(d: &[u8], at: usize) -> u64 {
    let mut b = [0u8; 8];
    b.copy_from_slice(&d[at..at + 8]);
    u64::from_be_bytes(b)
}

fn le32(d: &[u8], at: usize) -> u32 {
    u32::from_le_bytes([d[at], d[at + 1], d[at + 2], d[at + 3]])
}

fn cpu_name(cputype: i32) -> String {
    match cputype {
        0x01000007 => "x86_64".into(),
        0x0100000C => "arm64".into(),
        7 => "i386".into(),
        12 => "arm".into(),
        n if n < 0 => format!("-0x{:x}", -(n as i64)),
        n => format!("0x{:x}", n),
    }
}

fn unpack_version(raw: u32) -> Version {
    (raw >> 16, (raw >> 8) & 0xFF, raw & 0xFF)
}

/// `data[start:end]`, clamped as a Python slice is.
fn slice(data: &[u8], start: u64, end: u64) -> &[u8] {
    let n = data.len() as u64;
    let a = start.min(n) as usize;
    let b = end.min(n) as usize;
    if a >= b {
        &[]
    } else {
        &data[a..b]
    }
}

/// `macho_slices(data)`: one slice per architecture; Ok(None) when `data`
/// is not a Mach-O; Err for one that cannot be read (Python's ValueError).
pub fn macho_slices(data: &[u8]) -> Result<Option<Vec<Slice>>, String> {
    if data.len() < 8 {
        return Ok(None);
    }
    let big = be32(data, 0);
    if big == FAT_MAGIC || big == FAT_MAGIC_64 {
        let count = be32(data, 4) as u64;
        if count == 0 || count > 32 {
            return Ok(None); // 0xCAFEBABE is also a Java class file.
        }
        let size: u64 = if big == FAT_MAGIC { 20 } else { 32 };
        if 8 + count * size > data.len() as u64 {
            return Err("its list of architectures runs past its end".into());
        }
        let mut slices = Vec::new();
        for index in 0..count {
            let at = (8 + index * size) as usize;
            let (offset, length) = if big == FAT_MAGIC {
                (be32(data, at + 8) as u64, be32(data, at + 12) as u64)
            } else {
                (be64(data, at + 8), be64(data, at + 16))
            };
            let thin = thin_slice(slice(data, offset, offset.saturating_add(length)))?;
            match thin {
                Some(t) => slices.push(t),
                None => return Err(format!("architecture {} is not a Mach-O", index)),
            }
        }
        return Ok(Some(slices));
    }
    Ok(thin_slice(data)?.map(|t| vec![t]))
}

/// `thin_slice(data)`: one architecture's Mach-O, or None.
pub fn thin_slice(data: &[u8]) -> Result<Option<Slice>, String> {
    if data.len() < 28 {
        return Ok(None);
    }
    let magic = le32(data, 0);
    if magic != MH_MAGIC && magic != MH_MAGIC_64 {
        return Ok(None);
    }
    let cputype = le32(data, 4) as i32;
    let ncmds = le32(data, 16);
    let mut at: usize = if magic == MH_MAGIC_64 { 32 } else { 28 };
    let mut oldest: Option<Version> = None;
    for _ in 0..ncmds {
        if at + 8 > data.len() {
            return Err("its load commands run past its end".into());
        }
        let cmd = le32(data, at);
        let cmdsize = le32(data, at + 4) as usize;
        if cmdsize < 8 || at + cmdsize > data.len() {
            return Err("a load command has a bad size".into());
        }
        if cmd == LC_BUILD_VERSION && cmdsize >= 16 {
            let platform = le32(data, at + 8);
            if platform == PLATFORM_MACOS {
                oldest = Some(unpack_version(le32(data, at + 12)));
            }
        } else if cmd == LC_VERSION_MIN_MACOSX && cmdsize >= 12 && oldest.is_none() {
            oldest = Some(unpack_version(le32(data, at + 8)));
        }
        at += cmdsize;
    }
    Ok(Some((cpu_name(cputype), oldest)))
}

#[cfg(test)]
mod tests {
    use super::*;

    const ARM64: i32 = 0x0100000C;
    const X86_64: i32 = 0x01000007;

    fn thin(cputype: i32, minos: Option<Version>, command: u32) -> Vec<u8> {
        let raw = minos.map_or(0, |(a, b, c)| (a << 16) | (b << 8) | c);
        let mut cmd = Vec::new();
        let put = |v: &mut Vec<u8>, x: u32| v.extend_from_slice(&x.to_le_bytes());
        match (minos, command) {
            (None, _) => {
                put(&mut cmd, 0x19);
                put(&mut cmd, 8);
            }
            (Some(_), 0x32) => {
                for x in [0x32, 24, 1, raw, raw, 0] {
                    put(&mut cmd, x);
                }
            }
            _ => {
                for x in [0x24, 16, raw, raw] {
                    put(&mut cmd, x);
                }
            }
        }
        let mut out = Vec::new();
        for x in [0xFEEDFACF, cputype as u32, 0, 2, 1, cmd.len() as u32, 0, 0] {
            put(&mut out, x);
        }
        out.extend(cmd);
        out.extend([0u8; 64]);
        out
    }

    fn fat(slices: &[(i32, Vec<u8>)]) -> Vec<u8> {
        let offset = 4096u32;
        let mut arches = Vec::new();
        let mut body: Vec<u8> = Vec::new();
        for (cpu, data) in slices {
            for x in [
                *cpu as u32,
                0,
                offset + body.len() as u32,
                data.len() as u32,
                12,
            ] {
                arches.extend_from_slice(&x.to_be_bytes());
            }
            body.extend(data);
        }
        let mut head = Vec::new();
        head.extend_from_slice(&0xCAFEBABEu32.to_be_bytes());
        head.extend_from_slice(&(slices.len() as u32).to_be_bytes());
        head.extend(arches);
        head.resize(offset as usize, 0);
        head.extend(body);
        head
    }

    #[test]
    fn reads_each_architecture_and_its_oldest_macos() {
        let universal = fat(&[
            (X86_64, thin(X86_64, Some((14, 0, 0)), 0x32)),
            (ARM64, thin(ARM64, Some((13, 5, 1)), 0x24)),
        ]);
        assert_eq!(
            macho_slices(&universal).unwrap().unwrap(),
            vec![
                ("x86_64".to_string(), Some((14, 0, 0))),
                ("arm64".to_string(), Some((13, 5, 1)))
            ]
        );
        assert_eq!(
            macho_slices(&thin(ARM64, None, 0x32)).unwrap().unwrap(),
            vec![("arm64".to_string(), None)]
        );
        assert_eq!(
            macho_slices(&thin(-5, None, 0x32)).unwrap().unwrap()[0].0,
            "-0x5"
        );
        assert_eq!(version_text((13, 5, 1)), "13.5.1");
        assert_eq!(version_text((14, 0, 0)), "14.0");
    }

    #[test]
    fn other_files_are_not_mach_o_and_broken_ones_are_errors() {
        assert_eq!(macho_slices(b"#!/bin/sh\n").unwrap(), None);
        assert_eq!(
            macho_slices(b"\xca\xfe\xba\xbe\x00\x00\x00\x00rest").unwrap(),
            None
        );
        let short = &fat(&[(ARM64, thin(ARM64, Some((14, 0, 0)), 0x32))])[..20];
        assert!(macho_slices(short).is_err());
        let mut bad = thin(ARM64, Some((14, 0, 0)), 0x32);
        bad[36..40].copy_from_slice(&4u32.to_le_bytes());
        assert!(macho_slices(&bad).is_err());
    }
}
