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

"""Generates checked-in jq 1.8.2 parity test cases from /opt/homebrew/bin/jq.

All escape-sensitive literals are constructed in Python with BS = chr(92) so
shell/prompt escaping cannot mutate backslashes or \\uXXXX sequences.
"""

from __future__ import annotations

import os
import subprocess
import sys

JQ_BIN = "/opt/homebrew/bin/jq"
BS = chr(92)


def run_jq(args: list[str], inp: bytes) -> tuple[int, bytes, bytes]:
    proc = subprocess.run([JQ_BIN] + args, input=inp, capture_output=True, check=False)
    return proc.returncode, proc.stdout, proc.stderr


def ensure_jq_182() -> str:
    proc = subprocess.run(
        [JQ_BIN, "--version"], capture_output=True, text=True, check=True
    )
    ver = proc.stdout.strip()
    if not ver.startswith("jq-1.8."):
        raise RuntimeError(f"Expected jq 1.8.x at {JQ_BIN}, got {ver!r}")
    return ver


def build_cases() -> list[tuple[str, str, str, str, bytes]]:
    """Returns list of (id, op, flags, jq_args, jq_filter, input_bytes) tuples mapped cleanly."""
    cases: list[tuple[str, str, str, list[str], bytes]] = []

    def add(
        cid: str, op: str, flags: str, jq_args: list[str], inp: bytes | str
    ) -> None:
        raw = inp.encode("utf-8") if isinstance(inp, str) else inp
        cases.append((cid, op, flags, jq_args, raw))

    # -----------------------------------------------------------------------
    # 1. Pretty, compact (-c), raw (-r), sorted (-S), -rc, -rS, -Sc
    # -----------------------------------------------------------------------
    sample_obj = b'{"z":1,"a":{"d":[1,true,false,null,"x"],"c":{}},"m":[],"empty":{}}'
    add("fmt_pretty_obj", "id", "pretty", ["."], sample_obj)
    add("fmt_compact_obj", "id", "compact", ["-c", "."], sample_obj)
    add("fmt_sorted_obj", "id", "sorted", ["-S", "."], sample_obj)
    add("fmt_sorted_compact_obj", "id", "sorted_compact", ["-Sc", "."], sample_obj)
    add("fmt_raw_obj", "id", "raw", ["-r", "."], sample_obj)
    add("fmt_raw_compact_obj", "id", "raw_compact", ["-rc", "."], sample_obj)
    add("fmt_raw_sorted_obj", "id", "raw_sorted", ["-rS", "."], sample_obj)

    add("fmt_raw_str", "id", "raw", ["-r", "."], b'"hello\\nworld"')
    add("fmt_pretty_str", "id", "pretty", ["."], b'"hello\\nworld"')
    add("fmt_raw_num", "id", "raw", ["-r", "."], b"42")
    add("fmt_raw_bool", "id", "raw", ["-r", "."], b"false")
    add("fmt_raw_null", "id", "raw", ["-r", "."], b"null")
    add("fmt_dup_keys", "id", "pretty", ["."], b'{"b":1,"a":2,"b":3,"c":4,"a":5}')
    add(
        "fmt_dup_keys_sorted",
        "id",
        "sorted",
        ["-S", "."],
        b'{"b":1,"a":2,"b":3,"c":4,"a":5}',
    )
    add(
        "fmt_sorted_key_order",
        "id",
        "sorted_compact",
        ["-Sc", "."],
        '{"b":1,"a":2,"\\u0000":3,"A":4,"é":5,"😀":6}',
    )
    add(
        "fmt_sorted_nested_arr",
        "id",
        "sorted",
        ["-S", "."],
        b'[{"z":1,"a":2},{"d":{"y":1,"x":2}}]',
    )

    # Escapes & controls (with BS = chr(92))
    esc_input = (
        '"'
        + BS
        + "u0000"
        + BS
        + "u0001"
        + BS
        + "u0007"
        + BS
        + "b"
        + BS
        + "t"
        + BS
        + "n"
        + BS
        + "u000b"
        + BS
        + "f"
        + BS
        + "r"
        + BS
        + "u001f"
        + BS
        + "u007f"
        + BS
        + '"'
        + BS
        + BS
        + BS
        + '/é😀"'
    ).encode("utf-8")
    add("fmt_escapes_compact", "id", "compact", ["-c", "."], esc_input)
    add("fmt_escapes_raw", "id", "raw", ["-r", "."], esc_input)
    add(
        "fmt_c1_u2028",
        "id",
        "compact",
        ["-c", "."],
        ('"' + BS + "u0080" + BS + "u009f" + BS + "u2028" + BS + 'u2029"').encode(
            "utf-8"
        ),
    )
    add(
        "fmt_surrogate_pair",
        "id",
        "compact",
        ["-c", "."],
        ('"' + BS + "ud83d" + BS + 'ude00"').encode("utf-8"),
    )
    add(
        "fmt_lone_low_surrogate",
        "id",
        "compact",
        ["-c", "."],
        ('"' + BS + 'udc00"').encode("utf-8"),
    )
    add("fmt_raw_del_char", "id", "compact", ["-c", "."], b'"a\x7fb"')

    # -----------------------------------------------------------------------
    # 2. jq 1.8 decNumber literals & formatting
    # -----------------------------------------------------------------------
    num_literals = [
        "0",
        "-0",
        "0.0",
        "-0.0",
        "1",
        "1.0",
        "1.000",
        "01",
        "-01",
        "+1",
        "+0.0",
        ".5",
        "-.5",
        "+.5",
        "1.",
        "1.e2",
        ".5e2",
        "1E2",
        "1e2",
        "1e+2",
        "0.1e1",
        "1.0e+0",
        "1e+00",
        "1e-00",
        "0e0",
        "0.0e0",
        "-0e0",
        "0.10",
        "1.5e-7",
        "0.000001",
        "0.0000001",
        "0.0000010",
        "0.0000000",
        "0.000000",
        "-0.000000",
        "-0.0000000",
        "0e5",
        "0e-6",
        "0e-7",
        "0.0e-6",
        "0.0e-7",
        "123e-2",
        "-1.20E+3",
        "0.100e-5",
        "0.100e-6",
        "000.000",
        "001.200",
        "1e6",
        "1e7",
        "1e20",
        "1e21",
        "100000000000000000001",
        "100000000000000000000",
        "1.5e300",
        "1e309",
        "-1e309",
        "1e1000",
        "1e-400",
        "1e999999999",
        "1e-999999999",
        "1e1000000000",
        "-1e1000000000",
        "0e1000000000",
        "0e-1000000000",
        "1e-1000000000",
        "Infinity",
        "-Infinity",
        "+Infinity",
        "inf",
        "-inf",
        "NaN",
        "nan",
        "-nan",
        "+snan",
    ]
    for idx, lit in enumerate(num_literals):
        add(f"num_{idx:02d}", "id", "compact", ["-c", "."], lit.encode("ascii"))

    # -----------------------------------------------------------------------
    # 3. tostring & string interpolation
    # -----------------------------------------------------------------------
    add(
        "tostring_types",
        "tostring_all",
        "compact",
        ["-c", "[.[] | tostring]"],
        b'[null,true,false,0,-0,1.0,1E2,"hi","a\\nb",[1,2],{"b":1,"a":2},nan,Infinity]',
    )
    add(
        "interp_str",
        "interp_kv",
        "raw",
        ["-r", '"k=\\(.a) v=\\(.b)"'],
        b'{"a":"hi","b":123}',
    )
    add("interp_err_order", "interp_kv", "raw", ["-r", '"k=\\(.a) v=\\(.b)"'], b"5")
    add("interp_complex", "interp_self", "raw", ["-r", '"\\(.)"'], b'{"b":1,"a":[1,2]}')
    add("interp_null", "interp_self", "raw", ["-r", '"\\(.)"'], b"null")

    # -----------------------------------------------------------------------
    # 4. Total ordering: sort, sort_by, group_by, unique, unique_by
    # -----------------------------------------------------------------------
    add(
        "sort_all_types",
        "sort",
        "compact",
        ["-c", "sort"],
        b'[1,"a",null,false,true,[],{},[1],{"a":1},nan,-1e309,-Infinity,1e309,Infinity,-0,0]',
    )
    add(
        "sort_numbers_precision",
        "sort",
        "compact",
        ["-c", "sort"],
        b"[100000000000000000001,100000000000000000000,1e1000,1e999,-1e1000,-1e999,1e-1000,1e-1001,0,-0]",
    )
    add(
        "sort_objects_keys_before_vals",
        "sort",
        "compact",
        ["-c", "sort"],
        b'[{"a":2},{"a":1,"b":1},{"b":0},{"a":1},{"a":1,"c":0},{"a":2,"b":0},{}]',
    )
    add(
        "sort_strings_utf8",
        "sort",
        "compact",
        ["-c", "sort"],
        '["a","A","","\\u0000","é","😀","\\u0000a"]'.encode("utf-8"),
    )
    add(
        "sort_arrays",
        "sort",
        "compact",
        ["-c", "sort"],
        b"[[1,2],[1],[],[1,1,0],[null],[false]]",
    )
    add(
        "unique_mixed",
        "unique",
        "compact",
        ["-c", "unique"],
        b'[1,1.0,1.00,0,-0,0.0,0e5,nan,nan,null,{"b":2,"a":1},{"a":1,"b":2.0},[1],[1.0]]',
    )
    add(
        "sort_by_k",
        "sort_by_k",
        "compact",
        ["-c", "sort_by(.k)"],
        b'[{"k":2,"id":1},{"k":1,"id":2},{"k":1.0,"id":3},{"k":null,"id":4},{"k":false,"id":5}]',
    )
    add("sort_by_k_empty", "sort_by_k", "compact", ["-c", "sort_by(.k)"], b"[]")
    add("sort_by_k_err", "sort_by_k", "compact", ["-c", "sort_by(.k)"], b'[{"k":1},5]')
    add(
        "group_by_k",
        "group_by_k",
        "compact",
        ["-c", "group_by(.k)"],
        b'[{"k":2,"id":1},{"k":1,"id":2},{"k":1.0,"id":3},{"k":null,"id":4},{"k":nan,"id":5},{"k":nan,"id":6}]',
    )
    add("group_by_k_empty", "group_by_k", "compact", ["-c", "group_by(.k)"], b"[]")
    add(
        "unique_by_k",
        "unique_by_k",
        "compact",
        ["-c", "unique_by(.k)"],
        b'[{"k":2,"v":"a"},{"k":1,"v":"b"},{"k":1.0,"v":"c"},{"k":nan,"v":"d"},{"k":nan,"v":"e"}]',
    )

    # -----------------------------------------------------------------------
    # 5. Indexing, iterating, del, and jq 1.8 error text + truncation
    # -----------------------------------------------------------------------
    for name, inp in [
        ("null", b"null"),
        ("bool", b"true"),
        ("num", b"5"),
        ("str", b'"hi"'),
        ("arr", b"[1,2]"),
        ("obj_hit", b'{"foo":42}'),
        ("obj_miss", b'{"bar":42}'),
    ]:
        add(f"idx_foo_{name}", "idx_foo", "compact", ["-c", ".foo"], inp)

    for name, inp in [
        ("null", b"null"),
        ("bool", b"false"),
        ("num", b"7"),
        ("str", b'"abc"'),
        ("obj", b'{"a":1}'),
        ("arr_hit", b"[10,20,30]"),
        ("arr_empty", b"[]"),
    ]:
        add(f"idx_0_{name}", "idx_0", "compact", ["-c", ".[0]"], inp)
        add(f"idx_neg1_{name}", "idx_neg1", "compact", ["-c", ".[-1]"], inp)

    add("idx_oob_neg", "idx_neg4", "compact", ["-c", ".[-4]"], b"[10,20,30]")
    add("idx_float_pos", "idx_1_5", "compact", ["-c", ".[1.5]"], b"[10,20,30]")
    add("idx_float_pos_err", "idx_1_5", "compact", ["-c", ".[1.5]"], b'{"a":1}')
    add("idx_float_neg", "idx_neg0_5", "compact", ["-c", ".[-0.5]"], b"[10,20,30]")
    add(
        "idx_huge_num_err",
        "idx_huge",
        "compact",
        ["-c", ".[100000000000000000000000000000]"],
        b'{"a":1}',
    )

    for name, inp in [
        ("null", b"null"),
        ("bool", b"false"),
        ("num", b"42"),
        ("str", b'"hi"'),
        ("arr", b"[1,2]"),
        ("obj", b'{"a":1,"b":2}'),
    ]:
        add(f"iter_{name}", "iter", "compact", ["-c", ".[]"], inp)
        add(f"iter_opt_{name}", "iter_opt", "compact", ["-c", ".[]?"], inp)

    for name, inp in [
        ("null", b"null"),
        ("num", b"5"),
        ("str", b'"hi"'),
        ("arr", b"[1,2]"),
        ("bool", b"true"),
        ("obj_hit", b'{"a":1,"b":2}'),
        ("obj_miss", b'{"b":2}'),
    ]:
        add(f"del_a_{name}", "del_a", "compact", ["-c", "del(.a)"], inp)

    add("del_idx_1", "del_idx1", "compact", ["-c", "del(.[1])"], b"[10,20,30]")
    add("del_idx_neg1", "del_idx_neg1", "compact", ["-c", "del(.[-1])"], b"[10,20,30]")
    add("del_idx_oob", "del_idx99", "compact", ["-c", "del(.[99])"], b"[10,20,30]")
    add("del_idx_obj_err", "del_idx0", "compact", ["-c", "del(.[0])"], b'{"a":1}')

    # Truncation boundaries (30-byte buffer: <=29 exact, >29 cut to 25/26)
    for n in [26, 27, 28, 29, 35]:
        add(
            f"trunc_iter_str_{n}",
            "iter",
            "compact",
            ["-c", ".[]"],
            ('"' + "a" * n + '"').encode(),
        )
    add(
        "trunc_iter_utf8_23",
        "iter",
        "compact",
        ["-c", ".[]"],
        ('"' + "a" * 23 + "é" + "a" * 5 + '"').encode("utf-8"),
    )
    add(
        "trunc_iter_utf8_24",
        "iter",
        "compact",
        ["-c", ".[]"],
        ('"' + "a" * 24 + "é" + "a" * 5 + '"').encode("utf-8"),
    )
    add(
        "trunc_iter_emoji",
        "iter",
        "compact",
        ["-c", ".[]"],
        ('"' + "a" * 22 + "😀" + "a" * 5 + '"').encode("utf-8"),
    )
    add(
        "trunc_iter_escape_23",
        "iter",
        "compact",
        ["-c", ".[]"],
        ('"' + "a" * 23 + BS + "n" + "a" * 5 + '"').encode("ascii"),
    )
    add(
        "trunc_iter_escape_24",
        "iter",
        "compact",
        ["-c", ".[]"],
        ('"' + "a" * 24 + BS + "n" + "a" * 5 + '"').encode("ascii"),
    )
    add(
        "trunc_iter_num_29", "iter", "compact", ["-c", ".[]"], ("1" + "0" * 28).encode()
    )
    add(
        "trunc_iter_num_30", "iter", "compact", ["-c", ".[]"], ("1" + "0" * 29).encode()
    )
    add("trunc_idx_key_27", "idx_long27", "compact", ["-c", f'.["{"k" * 27}"]'], b"5")
    add("trunc_idx_key_28", "idx_long28", "compact", ["-c", f'.["{"k" * 28}"]'], b"5")
    add(
        "trunc_idx_key_utf8",
        "idx_long_utf8",
        "compact",
        ["-c", f'.["{"k" * 23}ékkkk"]'],
        b"5",
    )

    # -----------------------------------------------------------------------
    # 6. Multi-value streams, runtime error line numbers, and exit codes
    # -----------------------------------------------------------------------
    line_inputs = [
        ("no_nl", b"5"),
        ("one_nl", b"5\n"),
        ("sp_nl", b"5 \n"),
        ("multi_nl_after", b"5\n\n\n"),
        ("nl_before_1", b"\n5"),
        ("nl_before_2", b"\n\n5\n"),
        ("multiline_arr_no_nl", b"[1,\n2]"),
        ("multiline_arr_nl", b"[1,\n2]\n"),
        ("two_same_line_no_nl", b"5 6"),
        ("two_same_line_nl", b"5 6\n"),
        ("two_diff_lines_no_nl", b"5\n6"),
        ("two_diff_lines_nl", b"5\n6\n"),
        ("ok_then_err_same_line", b"{} 5\n"),
        ("ok_then_err_next_line", b"{}\n5"),
        ("multiline_arr_plus_5", b'["a",\n"b"] 5\n'),
        ("cr_lines", b"5\r6\n"),
        ("adj_strings", b'"a""b"'),
        ("adj_strings_nl", b'"a""b"\n'),
    ]
    for name, inp in line_inputs:
        add(f"line_{name}", "idx_x", "compact", ["-c", ".x"], inp)

    # Exit status matrix (default & -e)
    exit_inputs = [
        ("empty", "idx_a", b""),
        ("ws_only", "idx_a", b"  \n\t "),
        ("ok_1", "idx_a", b'{"a":1}'),
        ("ok_null", "idx_a", b"{}"),
        ("ok_false", "idx_a", b'{"a":false}'),
        ("err_only", "idx_a", b"5"),
        ("err_then_ok", "idx_a", b'5 {"a":1}'),
        ("err_then_null", "idx_a", b"5 {}"),
        ("err_then_false", "idx_a", b'5 {"a":false}'),
        ("ok_then_err", "idx_a", b'{"a":1} 5'),
        ("err_then_parse", "idx_a", b"5 {"),
        ("ok_then_parse", "idx_a", b'{"a":1} {'),
        ("parse_only", "idx_a", b"{"),
        ("each_ok_then_err", "iter_idx_a", b'[{"a":1},5]'),
        ("each_err_then_ok_val", "iter_idx_a", b'[{"a":1},5] [{"a":2}]'),
        ("empty_out", "empty_filter", b'{"a":1}'),
        ("ok_1_then_empty", "one_else_empty", b"1 2"),
        ("false_then_empty", "false_if_1_else_empty", b"1 2"),
        ("err_then_empty", "err_num_else_empty", b"5 {}"),
        ("ok_then_err_then_empty", "one_err_empty", b"1 5 {}"),
        ("false_then_err_then_empty", "false_err_empty", b"1 5 {}"),
    ]
    filter_exprs = {
        "idx_a": ".a",
        "iter_idx_a": ".[] | .a",
        "empty_filter": "empty",
        "one_else_empty": "if . == 1 then 1 else empty end",
        "false_if_1_else_empty": "if . == 1 then false else empty end",
        "err_num_else_empty": 'if type == "number" then .a else empty end',
        "one_err_empty": 'if . == 1 then 1 elif type == "number" then .a else empty end',
        "false_err_empty": 'if . == 1 then false elif type == "number" then .a else empty end',
    }
    for name, op, inp in exit_inputs:
        f = filter_exprs[op]
        add(f"exit_def_{name}", op, "compact", ["-c", f], inp)
        add(f"exit_e_{name}", op, "compact_exit", ["-ce", f], inp)

    # -----------------------------------------------------------------------
    # 7. Parse errors (jq 1.8.2 exact diagnostics)
    # -----------------------------------------------------------------------
    parse_bad = [
        ("open_brace", b"{"),
        ("open_bracket", b"["),
        ("obj_after_colon", b'{"a":'),
        ("obj_after_comma", b'{"a":1,'),
        ("obj_trailing_comma", b'{"a":1,}'),
        ("arr_after_comma", b"[1,"),
        ("arr_trailing_comma", b"[1,]"),
        ("arr_missing_comma", b"[1 2]"),
        ("arr_missing_comma_str", b'[1 "a"]'),
        ("arr_missing_comma_obj", b'[1 {"a":2}]'),
        ("obj_missing_comma", b'{"a":1 "b":2}'),
        ("obj_missing_comma_str", b'{"a":"b" "c":1}'),
        ("obj_num_key", b"{1:2}"),
        ("obj_bool_key", b"{true:1}"),
        ("obj_null_key", b"{null:1}"),
        ("obj_arr_key", b"{[]:1}"),
        ("obj_obj_key", b"{{}:1}"),
        ("single_quote_obj", b"{'a':1}"),
        ("single_quote_top", b"'a'"),
        ("unterminated_str", b'"abc'),
        ("unterminated_str_bs", b'"abc' + BS.encode()),
        ("bad_escape_q", ('"' + BS + 'q"').encode()),
        ("bad_u_short", ('"' + BS + 'u123"').encode()),
        ("bad_u_empty", ('"' + BS + 'u"').encode()),
        ("bad_u_hex", ('"' + BS + 'u123g"').encode()),
        ("unterminated_u", ('"' + BS + "u1234").encode()),
        ("lone_hi_surrogate", ('"' + BS + 'ud800"').encode()),
        ("bad_surrogate_pair_ascii", ('"' + BS + "ud800" + BS + 'u0041"').encode()),
        ("bad_surrogate_pair_hi", ('"' + BS + "ud800" + BS + 'ud800"').encode()),
        ("bad_surrogate_pair_short", ('"' + BS + "ud800" + BS + 'u123"').encode()),
        ("bad_surrogate_pair_x", ('"' + BS + 'ud800x"').encode()),
        ("raw_nl_in_str", b'"a\nb"'),
        ("raw_tab_in_str", b'"a\tb"'),
        ("raw_nul_in_str", b'"a\x00b"'),
        ("raw_cr_in_str", b'"a\rb"'),
        ("lit_tru", b"tru"),
        ("lit_tru_nl", b"\n  tru\n"),
        ("lit_truee", b"truee"),
        ("lit_fals", b"fals"),
        ("lit_nul", b"nul"),
        ("lit_foo", b"foo"),
        ("num_nanx", b"nanx"),
        ("num_nan123", b"nan123"),
        ("num_n", b"n"),
        ("num_na", b"na"),
        ("num_s", b"s"),
        ("num_minus", b"-"),
        ("num_plus", b"+"),
        ("num_dot", b"."),
        ("num_minus_dot", b"-."),
        ("num_1e", b"1e"),
        ("num_1e_plus", b"1e+"),
        ("num_1_2_3", b"1.2.3"),
        ("num_1a", b"1a"),
        ("num_0x1", b"0x1"),
        ("unmatched_rbracket", b"]"),
        ("unmatched_rbrace", b"}"),
        ("leading_comma", b","),
        ("leading_colon", b":"),
        ("trailing_x", b'{"a":1}x'),
        ("trailing_rbracket_after_num", b"1]"),
        ("trailing_rbracket_after_obj", b"{}]"),
        ("trailing_rbracket_after_str", b'"a"]'),
        ("obj_no_colon_close", b'{"a"}'),
        ("obj_no_colon_comma", b'{"a",}'),
        ("obj_double_colon", b'{"a":1:2}'),
        ("arr_colon", b"[1:2]"),
        ("obj_missing_val_close", b'{"a":}'),
        ("obj_double_comma", b'{"a":1,,}'),
        ("arr_double_comma", b"[1,,2]"),
        ("arr_empty_comma", b"[,]"),
        ("obj_empty_comma", b"{,}"),
        ("top_colon_after_arr", b"[1]:2"),
        ("top_comma_after_obj", b'{"a":1},'),
        ("second_val_bad", b'{"a":1}\n\n"bad'),
        ("bom_valid", b"\xef\xbb\xbf1"),
        ("bom_unfinished", b"\xef\xbb\xbf{"),
        ("bom_mid_stream", b"1 \xef\xbb\xbf 2"),
        ("double_bom", b"\xef\xbb\xbf\xef\xbb\xbf1"),
        ("ws_before_bom", b"  \xef\xbb\xbf1"),
        ("raw_ff_top", b"\xff"),
        ("invalid_utf8_in_str_c0af", b'"\xc0\xaf"'),
        ("invalid_utf8_in_str_f4", b'"\xf4\x90\x80\x80"'),
        ("invalid_utf8_in_str_surr", b'"\xed\xa0\x80"'),
        ("invalid_utf8_in_str_split", b'"\xf1\x80A\x80"'),
        ("invalid_utf8_in_str_trunc", b'"\xe0\xa0"'),
    ]
    for name, inp in parse_bad:
        add(f"parse_{name}", "id", "compact", ["-c", "."], inp)

    # -----------------------------------------------------------------------
    # 8. Round 2 regression parity cases (colon/key errors, mismatched
    #    brackets, and decNumber etiny/emax exponent boundaries)
    # -----------------------------------------------------------------------
    round2_parse_bad = [
        # Colon & key error branches
        ("top_colon_after_num", b"1:2"),
        ("top_colon_after_num_sp", b"1 : 2"),
        ("top_colon_after_true", b"true:1"),
        ("top_colon_after_false", b"false:1"),
        ("top_colon_after_null", b"null:1"),
        ("top_colon_after_str", b'"a":1'),
        ("top_colon_after_obj", b'{"a":1}:2'),
        ("top_colon_after_two_nums", b"1 2:3"),
        ("arr_empty_colon", b"[:]"),
        ("arr_colon_after_comma", b"[1,:2]"),
        ("arr_str_colon", b'["a":1]'),
        ("arr_bool_colon", b"[true:1]"),
        ("arr_null_colon", b"[null:1]"),
        ("arr_arr_colon", b"[[]:1]"),
        ("arr_obj_colon", b"[{}:1]"),
        ("obj_leading_colon", b"{:1}"),
        ("obj_empty_colon", b"{:}"),
        ("obj_colon_after_comma", b'{"a":1,:2}'),
        ("obj_adjacent_double_colon", b'{"a"::1}'),
        ("obj_second_key_double_colon", b'{"a":1,"b"::2}'),
        ("obj_val_str_colon", b'{"a":"b":1}'),
        ("obj_val_bool_colon", b'{"a":true:1}'),
        ("obj_second_num_key", b'{"a":1,1:2}'),
        ("obj_second_bool_key", b'{"a":1,true:2}'),
        ("obj_false_key", b"{false:1}"),
        # Mismatched brackets & unexpected closes
        ("mismatch_arr_rbrace_empty", b"[}"),
        ("mismatch_obj_rbracket_empty", b"{]"),
        ("mismatch_arr_val_rbrace", b"[1}"),
        ("mismatch_arr_comma_rbrace", b"[1,}"),
        ("mismatch_arr_two_vals_rbrace", b"[1,2}"),
        ("mismatch_arr_str_rbrace", b'["a"}'),
        ("mismatch_arr_str_comma_rbrace", b'["a",}'),
        ("mismatch_arr_nested_arr_rbrace", b"[[1]}"),
        ("mismatch_arr_nested_obj_rbrace", b"[{}}"),
        ("mismatch_obj_key_rbracket", b'{"a"]'),
        ("mismatch_obj_colon_rbracket", b'{"a":]'),
        ("mismatch_obj_val_rbracket", b'{"a":1]'),
        ("mismatch_obj_comma_rbracket", b'{"a":1,]'),
        ("mismatch_obj_num_rbracket", b"{1]"),
        ("mismatch_obj_num_rbrace", b"{1}"),
        ("mismatch_obj_key_comma_rbracket", b'{"a",]'),
        ("mismatch_nested_arr_obj_rbracket", b"[{]"),
        ("mismatch_nested_arr_obj_val_rbracket", b'[{"a":1]'),
        ("mismatch_nested_arr_obj_comma_rbracket", b'[{"a":1,]'),
        ("mismatch_nested_obj_arr_rbrace", b'{"a":[}'),
        ("mismatch_nested_obj_arr_val_rbrace", b'{"a":[1}'),
        ("mismatch_nested_obj_arr_comma_rbrace", b'{"a":[1,}'),
        ("mismatch_nested_arr_multiline_rbrace", b"[\n1\n}"),
        ("top_num_rbrace", b"1}"),
        ("top_num_sp_rbrace", b"1 }"),
        ("top_str_rbrace", b'"a"}'),
        ("top_arr_rbrace", b"[]}"),
        ("top_obj_extra_rbrace", b'{"a":1}}'),
    ]
    for name, inp in round2_parse_bad:
        add(f"parse_{name}", "id", "compact", ["-c", "."], inp)

    round2_num_limits = [
        ("num_emax_multi_ok", b"10e999999998"),
        ("num_emax_multi_overflow", b"10e999999999"),
        ("num_emax_frac_ok", b"0.1e1000000000"),
        ("num_emax_frac_overflow", b"0.1e1000000001"),
        ("num_emax_zero_frac_below", b"0.0e999999999"),
        ("num_emax_zero_frac_exact", b"0.0e1000000000"),
        ("num_emax_zero_frac_clamp", b"0.0e1000000001"),
        ("num_emax_neg_zero_clamp", b"-0e1000000000"),
        ("num_emax_huge", b"1e99999999999999999999"),
        ("num_etiny_exact", b"1e-1147483646"),
        ("num_etiny_underflow", b"1e-1147483647"),
        ("num_etiny_neg_exact", b"-1e-1147483646"),
        ("num_etiny_neg_underflow", b"-1e-1147483647"),
        ("num_etiny_zero_exact", b"0e-1147483646"),
        ("num_etiny_zero_clamp", b"0e-1147483647"),
        ("num_etiny_neg_zero_clamp", b"-0e-1147483647"),
        ("num_etiny_zero_frac_clamp", b"0.00e-1147483645"),
        ("num_etiny_round_down_4", b"4e-1147483647"),
        ("num_etiny_round_half_up_5", b"5e-1147483647"),
        ("num_etiny_round_neg_5", b"-5e-1147483647"),
        ("num_etiny_round_5_below", b"5e-1147483648"),
        ("num_etiny_round_half_up_25", b"25e-1147483647"),
        ("num_etiny_round_half_up_15", b"15e-1147483647"),
        ("num_etiny_round_12", b"12e-1147483647"),
        ("num_etiny_round_carry_95", b"9.5e-1147483646"),
        ("num_etiny_round_carry_995", b"99.5e-1147483646"),
        ("num_etiny_multidigit_exact", b"1.23456e-1147483641"),
        ("num_etiny_multidigit_round1", b"1.23456e-1147483642"),
        ("num_etiny_multidigit_round5", b"1.23456e-1147483646"),
        ("num_etiny_multidigit_zero", b"1.23456e-1147483647"),
        ("num_etiny_frac_offset_ok", b"0.00000000001e-1147483635"),
        ("num_etiny_frac_offset_underflow", b"0.00000000001e-1147483636"),
        ("num_etiny_huge_neg", b"1e-99999999999999999999"),
    ]
    for cid, inp in round2_num_limits:
        add(cid, "id", "compact", ["-c", "."], inp)

    add(
        "num_etiny_sort",
        "sort",
        "compact",
        ["-c", "sort"],
        b"[1e-1147483647,1e-1147483646,0,-1e-1147483646,-1e-1147483647]",
    )
    add(
        "num_etiny_unique",
        "unique",
        "compact",
        ["-c", "unique"],
        b"[1e-1147483647,0,-1e-1147483647]",
    )

    # -----------------------------------------------------------------------
    # 9. Round 3 regression parity cases (EOF separator errors)
    # -----------------------------------------------------------------------
    round3_eof_sep = [
        ("eof_sep_arr_sp_nums", b"[ 1 1"),
        ("eof_sep_arr_nums_11", b"[1 1"),
        ("eof_sep_arr_str_num_nosp", b'["a"1'),
        ("eof_sep_arr_str_num_sp", b'["a" 1'),
        ("eof_sep_obj_sp_str_num", b'{ "a" 1'),
        ("eof_sep_obj_str_num_nosp", b'{"a"1'),
        ("eof_sep_arr_sp_true_null", b"[ true null"),
        ("eof_sep_arr_true_null_nosp", b"[true null"),
        ("eof_sep_arr_num_str_sp", b'[1 "a"'),
        ("eof_sep_arr_num_str_nosp", b'[1"a"'),
        ("eof_sep_arr_1_2", b"[1 2"),
        ("eof_sep_arr_1_2_trailing_sp", b"[1 2 "),
        ("eof_sep_arr_12_unclosed", b"[12"),
        ("eof_sep_arr_str_str_nosp", b'["a""b"'),
        ("eof_sep_obj_val_num", b'{"a":1 2'),
        ("eof_sep_obj_val_bool", b'{"a":1 true'),
        ("eof_sep_obj_val_str_nosp", b'{"a":1"b"'),
        ("eof_sep_obj_str_val_num_nosp", b'{"a":"b"1'),
        ("eof_sep_nested_arr_num_nosp", b"[[1]1"),
        ("eof_sep_nested_obj_num_nosp", b"[{}1"),
        ("eof_sep_arr_num_str_esc", ('[1 "a' + BS + 'n"').encode("ascii")),
        ("eof_sep_arr_multiline", b"[\n1\n2"),
        ("eof_sep_after_top_val", b"1 [ 1 1"),
    ]
    for name, inp in round3_eof_sep:
        add(f"parse_{name}", "id", "compact", ["-c", "."], inp)

    # -----------------------------------------------------------------------
    # 10. Combinators: or_empty, alt, first, any
    # -----------------------------------------------------------------------
    for name, inp in [
        ("empty_obj", b"{}"),
        ("false", b'{"a":false}'),
        ("zero", b'{"a":0}'),
        ("empty_str", b'{"a":""}'),
        ("ok", b'{"a":"ok"}'),
        ("err_str", b'"str"'),
        ("err_then_ok", b'[1] {"a":"ok"}'),
        ("ok_then_err", b'{"a":"ok"} [1]'),
    ]:
        add(
            f"or_empty_c_{name}",
            "idx_a_or_empty",
            "compact",
            ["-c", ".a // empty"],
            inp,
        )
        add(f"or_empty_r_{name}", "idx_a_or_empty", "raw", ["-r", ".a // empty"], inp)

    for name, inp in [
        ("empty_arr", b"[]"),
        ("all_falsy", b'[{"a":false},{"a":null}]'),
        ("mixed", b'[{"a":false},{"a":1},{"a":null},{"a":2}]'),
        ("falsy_then_err", b'[{"a":false},5]'),
        ("falsy_truthy_err", b'[{"a":false},{"a":1},5]'),
        ("err_then_truthy", b'[5,{"a":1}]'),
    ]:
        add(
            f"iter_or_empty_{name}",
            "iter_idx_a_or_empty",
            "compact",
            ["-c", "(.[] | .a) // empty"],
            inp,
        )

    for name, inp in [
        ("empty_obj", b"{}"),
        ("false", b'{"a":false}'),
        ("null", b'{"a":null}'),
        ("zero", b'{"a":0}'),
        ("empty_str", b'{"a":""}'),
        ("str_1", b'{"a":"1"}'),
        ("err_str", b'"str"'),
        ("err_then_null", b'5 {"a":null}'),
        ("null_then_err", b'{"a":null} 5'),
    ]:
        add(f"alt_c_{name}", "idx_a_alt_def", "compact", ["-c", '.a // "0"'], inp)
        add(f"alt_r_{name}", "idx_a_alt_def", "raw", ["-r", '.a // "0"'], inp)

    for name, inp in [
        ("empty_arr", b"[]"),
        ("all_falsy", b'[{"a":false},{"a":null}]'),
        ("mixed", b'[{"a":false},{"a":1},{"a":2}]'),
        ("falsy_then_err", b'[{"a":false},5]'),
        ("falsy_truthy_err", b'[{"a":false},{"a":1},5]'),
    ]:
        add(
            f"iter_alt_{name}",
            "iter_idx_a_alt_def",
            "compact",
            ["-c", '(.[] | .a) // "0"'],
            inp,
        )

    for name, inp in [
        ("hit", b'{"data":{"result":[{"value":[0,"1"]}]}}'),
        ("empty", b'{"data":{"result":[]}}'),
        ("false_val", b'{"data":{"result":[{"value":[0,false]}]}}'),
        ("bad_data", b'{"data":"bad"}'),
        ("err_str", b'"str"'),
    ]:
        add(
            f"prom_val_{name}",
            "prom_val",
            "raw",
            ["-r", '.data.result[0].value[1] // "0"'],
            inp,
        )

    for name, inp in [
        ("empty", b"[]"),
        ("two_hits", b'[{"a":1},{"a":2}]'),
        ("false_before_err", b'[{"a":false},5]'),
        ("null_before_err", b'[{"a":null},5]'),
        ("err_before_hit", b'[5,{"a":1}]'),
        ("err_top", b'"str"'),
    ]:
        add(
            f"first_iter_{name}",
            "first_iter_idx_a",
            "compact",
            ["-c", "first(.[] | .a)"],
            inp,
        )

    for name, inp in [
        (
            "short_circuit_after_hit",
            b'{"attachments":[{"fileName":"b","id":"0"},{"fileName":"a","id":"1"},"x"]}',
        ),
        ("err_before_hit", b'{"attachments":["x",{"fileName":"a","id":"1"}]}'),
        (
            "first_hit_false",
            b'{"attachments":[{"fileName":"a","id":false},{"fileName":"a","id":"2"}]}',
        ),
        (
            "first_hit_null",
            b'{"attachments":[{"fileName":"a","id":null},{"fileName":"a","id":"2"}]}',
        ),
        ("non_iter_attachments", b'{"attachments":5}'),
        ("err_top_str", b'"str"'),
        ("empty_stream", b""),
    ]:
        add(
            f"first_att_or_empty_{name}",
            "first_att_or_empty",
            "raw",
            ["-r", 'first(.attachments[]? | select(.fileName=="a") | .id) // empty'],
            inp,
        )

    for name, inp in [
        ("hit_before_err", b'{"attachments":[{"fileName":"a"},"x"]}'),
        ("err_before_hit", b'{"attachments":["x",{"fileName":"a"}]}'),
        ("miss", b'{"attachments":[{"fileName":"b"}]}'),
        ("non_iter", b'{"attachments":5}'),
        ("empty_obj", b"{}"),
        ("err_top_str", b'"str"'),
        ("empty_stream", b""),
        ("err_then_true", b'{"attachments":["x"]} {"attachments":[{"fileName":"a"}]}'),
        ("true_then_err", b'{"attachments":[{"fileName":"a"}]} {"attachments":["x"]}'),
    ]:
        add(
            f"any_att_c_{name}",
            "any_att",
            "compact",
            ["-c", 'any(.attachments[]?; .fileName == "a")'],
            inp,
        )
        add(
            f"any_att_ce_{name}",
            "any_att",
            "compact_exit",
            ["-ce", 'any(.attachments[]?; .fileName == "a")'],
            inp,
        )

    # -----------------------------------------------------------------------
    # 11. Depth limit parity cases (jq 1.8.2 MAX_PARSING_DEPTH = 10_000)
    # -----------------------------------------------------------------------
    def alternating(levels: int, arr_first: bool = True) -> bytes:
        parts: list[bytes] = []
        closers: list[bytes] = []
        for i in range(levels):
            is_arr = (i % 2 == 0) if arr_first else (i % 2 == 1)
            if is_arr:
                parts.append(b"[")
                closers.append(b"]")
            else:
                parts.append(b'{"a":')
                closers.append(b"}")
        return b"".join(parts) + b"1" + b"".join(reversed(closers))

    depth_cases = [
        ("depth_arr_10000_ok", b"[" * 10000 + b"]" * 10000),
        ("depth_arr_10001_err", b"[" * 10001 + b"]" * 10001),
        ("depth_obj_5000_ok", b'{"a":' * 5000 + b"1" + b"}" * 5000),
        ("depth_obj_5001_err", b'{"a":' * 5001 + b"1" + b"}" * 5001),
        ("depth_mixed_alt_6667_ok", alternating(6667, arr_first=True)),
        ("depth_mixed_alt_6668_err", alternating(6668, arr_first=True)),
        ("depth_obj4999_arr2_ok", b'{"a":' * 4999 + b"[[]]" + b"}" * 4999),
        ("depth_obj4999_arr3_err", b'{"a":' * 4999 + b"[[[]]]" + b"}" * 4999),
        ("depth_arr9999_obj_ok", b"[" * 9999 + b'{"a":1}' + b"]" * 9999),
        ("depth_arr9998_obj_arr_err", b"[" * 9998 + b'{"a":[]}' + b"]" * 9998),
        ("depth_arr10000_val_open_err", b"[" * 10000 + b"1[" + b"]" * 10000),
        ("depth_stream_ok_then_err", b"1 " + b"[" * 10001 + b"]" * 10001),
        ("depth_multiline_err", b"[\n" + b"[" * 10000 + b"]" * 10001),
        ("depth_trunc_arr_10001_err", b"[" * 10001),
    ]
    for cid, inp in depth_cases:
        add(cid, "id", "compact", ["-c", "."], inp)

    assert len(cases) >= 200, f"Expected >= 200 cases, got {len(cases)}"
    return cases


def main() -> int:
    ver = ensure_jq_182()
    verbose = "--verbose" in sys.argv[1:]
    cases = build_cases()
    repo_root = os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    )
    out_path = os.path.join(repo_root, "packages", "jq", "tests", "parity_cases.tsv")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    rows = ["id\top\tflags\tinput_hex\tstatus\tstdout_hex\tstderr_hex"]
    for cid, op, flags, jq_args, inp in cases:
        rc, out, err = run_jq(jq_args, inp)
        rows.append(
            f"{cid}\t{op}\t{flags}\t{inp.hex()}\t{rc}\t{out.hex()}\t{err.hex()}"
        )
        if verbose:
            print(f"{cid}: inp={inp!r} -> rc={rc} out={out!r} err={err!r}")

    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(rows) + "\n")

    print(f"Generated {len(cases)} parity cases with {ver} -> {out_path}")
    print("Sample repr audit:")
    for cid, op, flags, jq_args, inp in cases[:6]:
        rc, out, err = run_jq(jq_args, inp)
        print(f"  {cid}: inp={inp!r} rc={rc} out={out!r} err={err!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
