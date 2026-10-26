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

//! signing.py: signing the tool catalog, and checking a signature, the way
//! the app does. Ed25519; the private half is 32 bytes in base64 (the
//! repository secret CATALOG_SIGNING_KEY), the public half 32 bytes in
//! base64 (catalog/public-key.txt). The signature is over the exact bytes of
//! tools.json; tools.json.sig holds its 64 bytes in base64 and a newline.

use crate::{base64, crypto, pystr};

fn raw(text: &str, length: usize, what: &str) -> Result<Vec<u8>, String> {
    let raw = base64::b64decode_validate(pystr::strip(text))
        .ok_or_else(|| format!("the {} is not base64", what))?;
    if raw.len() != length {
        return Err(format!(
            "the {} is {} bytes, not {}",
            what,
            raw.len(),
            length
        ));
    }
    Ok(raw)
}

fn seed(private_b64: &str) -> Result<[u8; 32], String> {
    let raw = raw(private_b64, 32, "private key")?;
    let mut seed = [0u8; 32];
    seed.copy_from_slice(&raw);
    Ok(seed)
}

/// `public_key_of(private_b64)`: the public half, in base64.
pub fn public_key_of(private_b64: &str) -> Result<String, String> {
    Ok(base64::encode(&crypto::ed25519_public_key(&seed(
        private_b64,
    )?)))
}

/// `sign(data, private_b64)`: base64 of the 64 bytes, and a newline.
pub fn sign(data: &[u8], private_b64: &str) -> Result<Vec<u8>, String> {
    let signature = crypto::ed25519_sign(&seed(private_b64)?, data);
    let mut out = base64::encode(&signature).into_bytes();
    out.push(b'\n');
    Ok(out)
}

/// `verify(data, signature_file, public_b64)`: whether `signature_file` is a
/// signature of exactly `data` by the key whose public half is `public_b64`.
pub fn verify(data: &[u8], signature_file: &[u8], public_b64: &str) -> bool {
    let check = || -> Result<bool, String> {
        let public = raw(public_b64, 32, "public key")?;
        if !signature_file.is_ascii() {
            return Ok(false);
        }
        let text = std::str::from_utf8(signature_file).map_err(|e| e.to_string())?;
        let signature = raw(text, 64, "signature")?;
        let mut a = [0u8; 32];
        a.copy_from_slice(&public);
        let mut s = [0u8; 64];
        s.copy_from_slice(&signature);
        Ok(crypto::ed25519_verify(&a, data, &s))
    };
    check().unwrap_or(false)
}

/// A private key for one run, in base64: 32 bytes from the system's
/// random source, as `Ed25519PrivateKey.generate()` takes them.
pub fn new_key() -> std::io::Result<String> {
    use std::io::Read;
    let mut seed = [0u8; 32];
    std::fs::File::open("/dev/urandom")?.read_exact(&mut seed)?;
    Ok(base64::encode(&seed))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn b64_hex(hex: &str) -> String {
        let bytes: Vec<u8> = (0..hex.len() / 2)
            .map(|i| u8::from_str_radix(&hex[2 * i..2 * i + 2], 16).unwrap())
            .collect();
        base64::encode(&bytes)
    }

    const RFC: [(&str, &str, &[u8], &str); 2] = [
        (
            "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
            "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
            b"",
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
        ),
        (
            "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
            "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
            b"\x72",
            "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00",
        ),
    ];

    #[test]
    fn the_rfc_vectors() {
        for (private, public, message, signature) in RFC {
            assert_eq!(public_key_of(&b64_hex(private)).unwrap(), b64_hex(public));
            let made = sign(message, &b64_hex(private)).unwrap();
            assert_eq!(made, format!("{}\n", b64_hex(signature)).into_bytes());
            assert_eq!(made.len(), 89);
            assert!(verify(message, &made, &b64_hex(public)));
        }
    }

    #[test]
    fn a_changed_byte_or_another_key_is_refused() {
        let (private, public, _, _) = RFC[0];
        let other = RFC[1].1;
        let data = b"{\"version\": 1, \"generated\": \"2026-10-12T00:00:00Z\", \"tools\": []}\n";
        let signature = sign(data, &b64_hex(private)).unwrap();
        assert!(verify(data, &signature, &b64_hex(public)));
        let changed = String::from_utf8_lossy(data).replace("1,", "2,");
        assert!(!verify(changed.as_bytes(), &signature, &b64_hex(public)));
        let mut longer = data.to_vec();
        longer.push(b' ');
        assert!(!verify(&longer, &signature, &b64_hex(public)));
        assert!(!verify(data, &signature, &b64_hex(other)));
        assert!(!verify(data, b"not base64\n", &b64_hex(public)));
        let short = format!("{}\n", base64::encode(&[0u8; 63]));
        assert!(!verify(data, short.as_bytes(), &b64_hex(public)));
        assert!(!verify(data, b"\xff\n", &b64_hex(public)));
    }

    #[test]
    fn key_errors_in_pythons_words() {
        assert_eq!(
            public_key_of("not base64!").unwrap_err(),
            "the private key is not base64"
        );
        assert_eq!(
            public_key_of(&base64::encode(&[1u8; 31])).unwrap_err(),
            "the private key is 31 bytes, not 32"
        );
        assert!(new_key().unwrap().len() == 44);
    }

    #[test]
    fn the_public_key_is_a_point() {
        let text = include_str!("../public-key.txt");
        let raw = base64::b64decode_validate(pystr::strip(text)).unwrap();
        assert_eq!(raw.len(), 32);
        // A signature by some other key never verifies against it, and the
        // check does not panic on the real key.
        let (private, _, message, _) = RFC[0];
        let signature = sign(message, &b64_hex(private)).unwrap();
        assert!(!verify(message, &signature, pystr::strip(text)));
    }
}
