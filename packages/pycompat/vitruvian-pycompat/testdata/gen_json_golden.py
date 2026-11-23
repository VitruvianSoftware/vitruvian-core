# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""Deterministic input generator for `packages/pycompat/vitruvian-pycompat/testdata/json_golden.jsonl`.

How to regenerate `json_golden.jsonl`:
1. Generate the hex-encoded UTF-8 input corpus:
       /opt/homebrew/bin/python3.12 -I packages/pycompat/vitruvian-pycompat/testdata/gen_json_golden.py /tmp/golden_inputs.hex
2. Build `origin/main` `packages/pycompat/vitruvian-pycompat/src/lib.rs` as a
   standalone crate in a temporary directory (`rustc --edition 2021 -C opt-level=3`)
   and run a temporary driver that reads each hex line from `/tmp/golden_inputs.hex`,
   calls `loads(&input)` on `origin/main`, and writes one JSON object per line to
   `packages/pycompat/vitruvian-pycompat/testdata/json_golden.jsonl`:
     - Valid:     {"hex":"...","ok":true,"dumps":...,"py_repr":...}
     - Malformed: {"hex":"...","ok":false,"kind":"Decode","python_str":...,"line":N,"col":N,"pos":N}
"""

from __future__ import annotations

import random
import sys

BS = chr(92)
BOM = "\ufeff"
SEED = 0x5EED_C0DE_2026_1122


def rand_ws(rng: random.Random) -> str:
    choices = [" ", "\t", "\n", "\r", "\r\n"]
    return "".join(rng.choice(choices) for _ in range(rng.randrange(3)))


def rand_string_literal(rng: random.Random) -> str:
    tokens = [
        "",
        "a",
        "k",
        "dup",
        "key",
        "hello",
        "é",
        "😀",
        "日本語",
        f'{BS}"',
        f"{BS}{BS}",
        f"{BS}/",
        f"{BS}b",
        f"{BS}f",
        f"{BS}n",
        f"{BS}r",
        f"{BS}t",
        f"{BS}u0041",
        f"{BS}u00e9",
        f"{BS}ud83d{BS}ude00",
        f"{BS}ud800",
        f"{BS}udc00",
        f"{BS}udfff",
        f"{BS}ud800{BS}u0041",
        f"{BS}ud800{BS}ud83d{BS}ude00",
        f"{BS}udfff{BS}ud800",
        "it's",
    ]
    body = "".join(rng.choice(tokens) for _ in range(rng.randrange(5)))
    return f'"{body}"'


def rand_scalar(rng: random.Random) -> str:
    ints = [
        "0",
        "-0",
        "1",
        "-1",
        "42",
        "-999999999999999999",
        "170141183460469231731687303715884105728",
        "-170141183460469231731687303715884105729",
        "12345678901234567890123456789012345678901234567890",
    ]
    floats = [
        "0.0",
        "-0.0",
        "1.0",
        "123.456",
        "1e5",
        "1E-07",
        "1.5e+16",
        "1e400",
        "-1e400",
        "5e-324",
        "NaN",
        "Infinity",
        "-Infinity",
    ]
    kind = rng.randrange(6)
    if kind == 0:
        return "null"
    if kind == 1:
        return "true" if rng.randrange(2) == 0 else "false"
    if kind == 2:
        return rng.choice(ints)
    if kind == 3:
        return rng.choice(floats)
    if kind == 4:
        return rand_string_literal(rng)
    length = 39 + rng.randrange(40)
    sign = "-" if rng.randrange(2) == 0 else ""
    first = chr(ord("1") + rng.randrange(9))
    rest = "".join(chr(ord("0") + rng.randrange(10)) for _ in range(length - 1))
    return f"{sign}{first}{rest}"


def gen_valid_doc(rng: random.Random, depth: int, max_depth: int) -> str:
    if depth >= max_depth or (depth > 0 and rng.randrange(4) == 0):
        return rand_scalar(rng)
    kind = rng.randrange(3)
    if kind == 0:
        return rand_scalar(rng)
    if kind == 1:
        n = rng.randrange(4)
        parts = [gen_valid_doc(rng, depth + 1, max_depth) for _ in range(n)]
        sep = f"{rand_ws(rng)},{rand_ws(rng)}"
        return f"[{rand_ws(rng)}{sep.join(parts)}{rand_ws(rng)}]"
    n = rng.randrange(4)
    pairs = []
    for idx in range(n):
        key = (
            '"dup"' if (idx > 0 and rng.randrange(3) == 0) else rand_string_literal(rng)
        )
        val = gen_valid_doc(rng, depth + 1, max_depth)
        pairs.append(f"{key}{rand_ws(rng)}:{rand_ws(rng)}{val}")
    sep = f"{rand_ws(rng)},{rand_ws(rng)}"
    return f"{{{rand_ws(rng)}{sep.join(pairs)}{rand_ws(rng)}}}"


def gen_nested_chain(rng: random.Random, depth: int) -> str:
    openers = []
    closers = []
    for _ in range(depth):
        if rng.randrange(2) == 0:
            openers.append("[")
            closers.append("]")
        else:
            openers.append('{"k":')
            closers.append("}")
    leaf = rand_scalar(rng)
    return "".join(openers) + leaf + "".join(reversed(closers))


def gen_malformed_doc(rng: random.Random, valid_seed: str) -> str:
    kind = rng.randrange(11)
    if kind == 0:
        k = rng.randrange(max(1, len(valid_seed)))
        return valid_seed[:k]
    if kind == 1:
        return f"{BOM}{valid_seed}"
    if kind == 2:
        tail = rng.choice([" x", " 1", " []", " {}", ","])
        return f"{valid_seed}{tail}"
    if kind == 3:
        bad = [
            f'"{BS}x"',
            f'"{BS}q"',
            f'"{BS}0"',
            f'"{BS}u12"',
            f'"{BS}u123g"',
            f'"{BS}ud800{BS}u12"',
            f'"{BS}u0041',
            f'"ab{BS}u0041',
            f'"{BS}ud800{BS}u0041',
            f'"{BS}ud800{BS}udc00',
            f'"{BS}{BS}u0041',
            f'"ab{BS}',
        ]
        return rng.choice(bad)
    if kind == 4:
        ctrl = chr(rng.randrange(0x20))
        return f'"a{ctrl}b"'
    if kind == 5:
        fixed = [
            "[1,]",
            '{"a": 1,}',
            "[1 2]",
            '{"a" 1}',
            '{"a": 1 "b": 2}',
            "[,]",
            "{,}",
            "{1: 2}",
            '{"a":}',
        ]
        return rng.choice(fixed)
    if kind == 6:
        fixed = [
            "-",
            "-a",
            "-I",
            "-Inf",
            "01",
            "-01",
            "1.",
            "1e",
            "1e+",
            "1e-",
            ".5",
            "+1",
            "tru",
            "nul",
            "fals",
            "Na",
            "Inf",
            "nan",
            "True",
            "False",
            "Null",
        ]
        return rng.choice(fixed)
    if kind == 7 and valid_seed:
        chars = list(valid_seed)
        idx = rng.randrange(len(chars))
        chars[idx] = rng.choice(
            ["{", "}", "[", "]", ":", ",", '"', BS, "\n", "x", "0", "\x01"]
        )
        return "".join(chars)
    if kind == 8 and valid_seed:
        chars = list(valid_seed)
        idx = rng.randrange(len(chars) + 1)
        chars.insert(
            idx, rng.choice(["{", "}", "[", "]", ":", ",", '"', BS, "\x07", " "])
        )
        return "".join(chars)
    if kind == 9 and len(valid_seed) > 1:
        chars = list(valid_seed)
        chars.pop(rng.randrange(len(chars)))
        return "".join(chars)
    depth = 1 + rng.randrange(60)
    parts = ["[" if k % 2 == 0 else '{"k":' for k in range(depth)]
    return "".join(parts)


def build_inputs() -> list[str]:
    rng = random.Random(SEED)
    seen: set[str] = set()
    inputs: list[str] = []

    def add(s: str) -> None:
        if s not in seen:
            seen.add(s)
            inputs.append(s)

    # 1. Explicit scalar, escape, surrogate, astral, duplicate-key, BOM, and >4300-digit cases.
    big_4299 = "1" + ("0" * 4298)
    big_4300 = "1" + ("0" * 4299)
    big_4301 = "1" + ("0" * 4300)
    neg_4300 = "-" + ("9" * 4300)
    neg_4301 = "-" + ("9" * 4301)
    big_4500 = "7" + ("3" * 4499)

    pinned_valid = [
        "null",
        "true",
        "false",
        "0",
        "-0",
        "1",
        "-1",
        "0.0",
        "-0.0",
        "1.0",
        "1e5",
        "1E-07",
        "1.5e+16",
        "1e-16",
        "1e400",
        "-1e400",
        "5e-324",
        "NaN",
        "Infinity",
        "-Infinity",
        big_4299,
        big_4300,
        big_4301,
        neg_4300,
        neg_4301,
        big_4500,
        f"[{big_4300}, {neg_4300}, {big_4301}]",
        f'{{"big": {big_4301}, "neg": {neg_4301}}}',
        '""',
        '"simple"',
        '"it\'s"',
        '"é😀日本語"',
        f'"{BS}"{BS}{BS}{BS}/{BS}b{BS}f{BS}n{BS}r{BS}t"',
        f'"{BS}u0041{BS}u00e9{BS}u007f{BS}u0000{BS}u001f"',
        f'"{BS}ud83d{BS}ude00{BS}ud800{BS}udc00{BS}udbff{BS}udfff"',
        f'"{BS}ud800{BS}udc01{BS}ud800{BS}u0041{BS}udfff{BS}ud800"',
        f'"{BS}ud800"',
        f'"{BS}udc00"',
        f'"{BS}udfff"',
        "[]",
        "{}",
        '{"k": 1, "a": 2, "k": 3}',
        '{"k": 1, "k": 2, "k": 3}',
        f'{{"{BS}u0061": 1, "a": 2, "b": 3}}',
        f'{{"{BS}ud800": 1, "{BS}ud801": 2, "{BS}ud800": 3}}',
        f'{{"{BS}ud83d{BS}ude00": 1, "😀": 2}}',
        '[NaN, Infinity, -Infinity, {"a": [1, 2.0, -0, -0.0]}]',
        '  \t\r\n { "x" : [ true , false , null ] } \r\n ',
    ]
    for s in pinned_valid:
        add(s)

    # 2. All 151 deduplicated malformed CPython 3.12 parity inputs + extra malformed edge cases.
    pinned_malformed = [
        "",
        "\n",
        "\n\n  x",
        '\n"ab',
        " ",
        "  ",
        "  x",
        "   \n\t\r  ",
        f'"{BS}',
        f'"{BS}"',
        f'"{BS}\'"',
        f'"{BS}0"',
        f'"{BS}1"',
        f'"{BS}{BS}u0041',
        f'"{BS}a"',
        f'"{BS}q"',
        f'"{BS}u',
        f'"{BS}u 123"',
        f'"{BS}u0041',
        f'"{BS}u0041{BS}',
        f'"{BS}u0041x',
        f'"{BS}u1',
        f'"{BS}u12',
        f'"{BS}u12"',
        f'"{BS}u123',
        f'"{BS}u1234',
        f'"{BS}u123g"',
        f'"{BS}uZZZZ"',
        f'"{BS}ud800',
        f'"{BS}ud800{BS}u',
        f'"{BS}ud800{BS}u0041',
        f'"{BS}ud800{BS}u1',
        f'"{BS}ud800{BS}u12',
        f'"{BS}ud800{BS}u12"',
        f'"{BS}ud800{BS}u123',
        f'"{BS}ud800{BS}u123"',
        f'"{BS}ud800{BS}u123g"',
        f'"{BS}ud800{BS}udc00',
        f'"{BS}ud83d{BS}u12"',
        f'"{BS}ud83d{BS}ude00',
        f'"{BS}ud800{BS}uzzzz"',
        f'"{BS}ud83d{BS}uzzzz"x',
        f'"{BS}v"',
        f'"{BS}x"',
        '"a\x00b"',
        '"a\x01"',
        '"a\x01b"',
        '"a\x08b"',
        '"a\tb"',
        '"a\nb"',
        '"a\x0cb"',
        '"a\rb"',
        '"a\x1fb"',
        '"a""b"',
        f'"a{BS}q"',
        f'"a{BS}qb"',
        f'"a{BS}x"',
        '"ab',
        f'"ab{BS}',
        f'"ab{BS}u0041',
        '"abc',
        f'"abc{BS}u12"',
        f'"ok"{BS}',
        "+1",
        ",",
        "-",
        "--1",
        "-01",
        "-I",
        "-Inf",
        "-Infin",
        "-a",
        ".5",
        "00",
        "01",
        "1 2",
        "1 x",
        "1.",
        "1.e5",
        "1..2",
        "1.2.3",
        "1e",
        "1e+",
        "1e+a",
        "1e-",
        "1e-a",
        "1e1e1",
        ":",
        "False",
        "Inf",
        "Na",
        "Null",
        "True",
        "[",
        '[\n1,\n"x" 2]',
        '[\r\n1,\r\n"é" 2]',
        "[  ",
        f'["{BS}u0041',
        '["abc',
        '["😀" 2]',
        "[,]",
        "[01]",
        "[1",
        "[1 2]",
        "[1, 2 3]",
        "[1,]",
        "[1]\n x",
        "[[[",
        "[] []",
        "]]]",
        "fals",
        "infinity",
        "nan",
        "not json",
        "nul",
        "tru",
        "true false",
        "{",
        '{\n  "a": x\n}',
        '{\n  "a": 1,\n  "b": [1, 2,\n    "ok", tru]\n}',
        "{   ",
        '{"a"   1}',
        '{"a" 1}',
        '{"a":\n tru}',
        '{"a": ',
        '{"a": "b", "c" 3}',
        '{"a": 1',
        '{"a": 1 "b"}',
        '{"a": 1 "b": 2}',
        '{"a": 1, ',
        '{"a": 1,}',
        '{"a": [1, 2], "b": {"c":}}',
        '{"a":1 "b"}',
        '{"a":1,}',
        '{"a":1}x',
        '{"a":[1,2',
        '{"a":[}',
        '{"a":}',
        '{"a"}',
        '{"devices": [}',
        '{"k": "v',
        "{,}",
        "{1: 2}",
        "{a: 1}",
        "{broken",
        "{} x",
        "{}\n x",
        "}}}",
        BOM,
        f"{BOM}1",
        f"{BOM}{{}}",
        f"{BOM}[]",
        f'{BOM}"ok"',
    ]
    for s in pinned_malformed:
        add(s)

    # Every ASCII control character 0x00..=0x1F inside a string.
    for code in range(0x20):
        add(f'"x{chr(code)}y"')

    # 3. Random nesting chains up to depth 60 + all prefix truncations of a representative nested doc.
    for depth in [1, 2, 5, 10, 25, 40, 55, 60]:
        chain = gen_nested_chain(rng, depth)
        add(chain)
        if depth in (10, 60):
            # Prefix truncations along this nested chain.
            step = 1 if depth == 10 else 4
            for cut in range(1, len(chain), step):
                add(chain[:cut])

    # 4. Random valid & malformed documents targeting ~2,000 total cases (~1,000 valid, ~1,000 malformed).
    valid_pool: list[str] = []
    for i in range(950):
        bucket = i % 5
        if bucket == 0:
            max_d = 0
        elif bucket == 1:
            max_d = 1 + rng.randrange(5)
        elif bucket == 2:
            max_d = 6 + rng.randrange(12)
        elif bucket == 3:
            max_d = 18 + rng.randrange(20)
        else:
            max_d = 38 + rng.randrange(23)  # up to 60
        doc = f"{rand_ws(rng)}{gen_valid_doc(rng, 0, max_d)}{rand_ws(rng)}"
        # Keep individual fixtures reasonably sized.
        if len(doc) > 2048:
            doc = gen_nested_chain(rng, max_d)
        add(doc)
        valid_pool.append(doc)

    # Truncations of a sample of valid documents.
    for doc in valid_pool[:80]:
        if len(doc) > 2:
            cut = 1 + rng.randrange(len(doc) - 1)
            add(doc[:cut])

    # Generated malformed documents until we reach 2,000 total cases.
    idx = 0
    while len(inputs) < 2000:
        seed_doc = valid_pool[idx % len(valid_pool)]
        idx += 1
        add(gen_malformed_doc(rng, seed_doc))

    return inputs


def main() -> int:
    if len(sys.argv) > 2:
        print(f"usage: {sys.argv[0]} [output_hex_file]", file=sys.stderr)
        return 2
    inputs = build_inputs()
    lines = [s.encode("utf-8").hex() for s in inputs]
    payload = "\n".join(lines) + "\n"
    if len(sys.argv) == 2:
        with open(sys.argv[1], "w", encoding="utf-8") as f:
            f.write(payload)
    else:
        sys.stdout.write(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
