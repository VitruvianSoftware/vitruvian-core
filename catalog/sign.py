#!/usr/bin/env python3
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

"""Signs catalog/tools.json and writes the two files the website serves.

    CATALOG_SIGNING_KEY=<base64> bazel run //catalog:sign -- \
        --out apps/web/vitruviansoftware-dev/tools/catalog

It copies tools.json byte for byte and writes tools.json.sig beside it. It
refuses, and writes nothing, when the key's public half is not the one in
catalog/public-key.txt: a wrong secret must not publish a list the app will
refuse. Run by .github/workflows/catalog-publish.yaml; nobody needs to run it
by hand.
"""

import argparse
import os
import sys
from pathlib import Path

import signing


def main(argv=None):
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--catalog", type=Path, default=here / "tools.json")
    parser.add_argument("--public-key", type=Path, default=here / "public-key.txt")
    parser.add_argument("--key-env", default="CATALOG_SIGNING_KEY")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    workspace = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    out = (
        args.out
        if args.out.is_absolute() or not workspace
        else Path(workspace) / args.out
    )

    private = os.environ.get(args.key_env, "")
    if not private:
        print(f"sign: {args.key_env} is empty: nothing was signed", file=sys.stderr)
        return 2
    wanted = args.public_key.read_text(encoding="ascii").strip()
    try:
        have = signing.public_key_of(private)
    except ValueError as problem:
        print(f"sign: {problem}: nothing was signed", file=sys.stderr)
        return 2
    if have != wanted:
        print(
            f"sign: the key in {args.key_env} is not the one whose public half is in "
            f"{args.public_key.name} ({have} is not {wanted}): nothing was signed",
            file=sys.stderr,
        )
        return 2
    data = args.catalog.read_bytes()
    signature = signing.sign(data, private)
    if not signing.verify(data, signature, wanted):
        print(
            "sign: the signature does not verify: nothing was signed", file=sys.stderr
        )
        return 2
    out.mkdir(parents=True, exist_ok=True)
    (out / "tools.json").write_bytes(data)
    (out / "tools.json.sig").write_bytes(signature)
    print(f"sign: wrote {out / 'tools.json'} ({len(data)} bytes) and its signature")
    return 0


if __name__ == "__main__":
    sys.exit(main())
