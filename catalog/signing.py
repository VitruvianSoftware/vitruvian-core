# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Signing the tool catalog, and checking a signature, the way the app does.

The key is Ed25519. The private half is 32 bytes, kept in base64 as the
repository secret CATALOG_SIGNING_KEY; the public half is 32 bytes, in base64
in catalog/public-key.txt and in the app (CatalogueSigning.publicKey).

The signature is over the exact bytes of tools.json, with nothing added or
re-encoded. The file tools.json.sig holds the 64 bytes of the signature in
base64, then one newline: 89 bytes in all.
"""

import base64
import binascii

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)


def _raw(text, length, what):
    try:
        raw = base64.b64decode(text.strip(), validate=True)
    except (binascii.Error, ValueError):
        raise ValueError(f"the {what} is not base64") from None
    if len(raw) != length:
        raise ValueError(f"the {what} is {len(raw)} bytes, not {length}")
    return raw


def public_key_of(private_b64):
    """The public half of a private key, in base64, as public-key.txt holds it."""
    key = Ed25519PrivateKey.from_private_bytes(_raw(private_b64, 32, "private key"))
    raw = key.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    )
    return base64.b64encode(raw).decode("ascii")


def sign(data, private_b64):
    """The signature file for `data`: base64 of the 64 bytes, and a newline."""
    key = Ed25519PrivateKey.from_private_bytes(_raw(private_b64, 32, "private key"))
    return base64.b64encode(key.sign(data)) + b"\n"


def verify(data, signature_file, public_b64):
    """True when `signature_file` is a signature of exactly `data` by the key
    whose public half is `public_b64`."""
    try:
        key = Ed25519PublicKey.from_public_bytes(_raw(public_b64, 32, "public key"))
        key.verify(_raw(signature_file.decode("ascii"), 64, "signature"), data)
        return True
    except (InvalidSignature, ValueError, UnicodeDecodeError):
        return False
