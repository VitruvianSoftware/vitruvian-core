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

"""The catalog's signature: the same bytes in, the same answer as the app.

The first two cases are RFC 8032's own test vectors for Ed25519 (section 7.1,
TEST 1 and TEST 2). Their private keys are published in the RFC, so they are
no secret; no real key is in this repository.
"""

import base64
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import signing

HERE = Path(__file__).resolve().parent


def b64(hex_text):
    return base64.b64encode(bytes.fromhex(hex_text)).decode("ascii")


RFC_8032 = [
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
]


class SigningTest(unittest.TestCase):
    def test_the_rfc_vectors(self):
        for private, public, message, signature in RFC_8032:
            with self.subTest(public=public):
                self.assertEqual(signing.public_key_of(b64(private)), b64(public))
                made = signing.sign(message, b64(private))
                self.assertEqual(made, (b64(signature) + "\n").encode("ascii"))
                self.assertEqual(len(made), 89)
                self.assertTrue(signing.verify(message, made, b64(public)))

    def test_a_changed_byte_or_another_key_is_refused(self):
        private, public, _, _ = RFC_8032[0]
        _, other, _, _ = RFC_8032[1]
        data = b'{"version": 1, "generated": "2026-10-12T00:00:00Z", "tools": []}\n'
        signature = signing.sign(data, b64(private))
        self.assertTrue(signing.verify(data, signature, b64(public)))
        self.assertFalse(
            signing.verify(data.replace(b"1,", b"2,"), signature, b64(public))
        )
        self.assertFalse(signing.verify(data + b" ", signature, b64(public)))
        self.assertFalse(signing.verify(data, signature, b64(other)))
        self.assertFalse(signing.verify(data, b"not base64\n", b64(public)))
        self.assertFalse(
            signing.verify(data, base64.b64encode(b"\0" * 63) + b"\n", b64(public))
        )

    def test_the_public_key_is_a_key(self):
        text = (HERE / "public-key.txt").read_text(encoding="ascii")
        self.assertEqual(
            len(base64.b64decode(text.strip(), validate=True)),
            32,
            "public-key.txt holds 32 bytes in base64",
        )
        self.assertNotIn(
            text.strip(),
            [b64(public) for _, public, _, _ in RFC_8032],
            "the key is not a published test key",
        )

    def test_sign_writes_both_files_or_nothing(self):
        private, public, _, _ = RFC_8032[0]
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            (folder / "public-key.txt").write_text(b64(public) + "\n", encoding="ascii")
            (folder / "tools.json").write_bytes(b'{"version": 1}\n')

            def run(key, out):
                env = dict(os.environ, CATALOG_SIGNING_KEY=key)
                env.pop("BUILD_WORKSPACE_DIRECTORY", None)
                return subprocess.run(
                    [
                        sys.executable,
                        str(HERE / "sign.py"),
                        "--catalog",
                        str(folder / "tools.json"),
                        "--public-key",
                        str(folder / "public-key.txt"),
                        "--out",
                        str(out),
                    ],
                    env=env,
                    capture_output=True,
                    text=True,
                )

            wrong = run(b64(RFC_8032[1][0]), folder / "wrong")
            self.assertEqual(wrong.returncode, 2, wrong.stderr)
            self.assertIn("not the one whose public half", wrong.stderr)
            self.assertFalse((folder / "wrong").exists())
            self.assertEqual(run("", folder / "empty").returncode, 2)

            done = run(b64(private), folder / "site")
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertEqual(
                (folder / "site/tools.json").read_bytes(), b'{"version": 1}\n'
            )
            self.assertTrue(
                signing.verify(
                    b'{"version": 1}\n',
                    (folder / "site/tools.json.sig").read_bytes(),
                    b64(public),
                )
            )


if __name__ == "__main__":
    unittest.main()
