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
"""Writes src/unicode_tables.rs: the character facts sdk_codegen.py and the
libraries it uses get from Python, so the Rust port answers them the same way.

    python3 tools/sdk-codegen/gen_unicode_tables.py > tools/sdk-codegen/src/unicode_tables.rs

Run it with the Python the generator runs on (3.12). sdk_codegen_rs_parity_test
regenerates the file and fails when it differs, so a Python whose Unicode data
moved shows up as a failing test, not as a quiet disagreement.
"""

import re
import sys
import unicodedata

with open(__file__, encoding="utf-8") as _handle:
    HERE_LICENSE = _handle.read().split('"""', 1)[0]


def ranges(test):
    out, start = [], None
    for c in range(0x110000):
        if test(c):
            if start is None:
                start = c
        elif start is not None:
            out.append((start, c - 1))
            start = None
    if start is not None:
        out.append((start, 0x10FFFF))
    return out


def table(name, pairs, what):
    # One pair a line: the layout rustfmt gives it, so formatting the
    # repository leaves the file as generated.
    lines = [f"/// {what}", f"pub static {name}: &[(u32, u32)] = &["]
    lines += [f"    (0x{lo:X}, 0x{hi:X})," for lo, hi in pairs]
    lines.append("];")
    return "\n".join(lines)


def mapping(name, change, what):
    lines = [f"/// {what}", f"pub static {name}: &[(u32, &str)] = &["]
    for c in range(0x110000):
        if 0xD800 <= c <= 0xDFFF:
            continue
        mapped = change(chr(c))
        if mapped != chr(c):
            text = "".join(f"\\u{{{ord(m):X}}}" for m in mapped)
            lines.append(f'    (0x{c:X}, "{text}"),')
    lines.append("];")
    return "\n".join(lines)


# The formal name aliases of Unicode 15.0.0 (NameAliases.txt), which
# unicodedata.lookup, and so re's \\N{...}, accepts but cannot list.
# render() checks each still names a character in this Python.
ALIASES = (
    "NULL",
    "NUL",
    "START OF HEADING",
    "SOH",
    "START OF TEXT",
    "STX",
    "END OF TEXT",
    "ETX",
    "END OF TRANSMISSION",
    "EOT",
    "ENQUIRY",
    "ENQ",
    "ACKNOWLEDGE",
    "ACK",
    "ALERT",
    "BEL",
    "BACKSPACE",
    "BS",
    "CHARACTER TABULATION",
    "HORIZONTAL TABULATION",
    "HT",
    "TAB",
    "LINE FEED",
    "NEW LINE",
    "END OF LINE",
    "LF",
    "NL",
    "EOL",
    "LINE TABULATION",
    "VERTICAL TABULATION",
    "VT",
    "FORM FEED",
    "FF",
    "CARRIAGE RETURN",
    "CR",
    "SHIFT OUT",
    "LOCKING-SHIFT ONE",
    "SO",
    "SHIFT IN",
    "LOCKING-SHIFT ZERO",
    "SI",
    "DATA LINK ESCAPE",
    "DLE",
    "DEVICE CONTROL ONE",
    "DC1",
    "DEVICE CONTROL TWO",
    "DC2",
    "DEVICE CONTROL THREE",
    "DC3",
    "DEVICE CONTROL FOUR",
    "DC4",
    "NEGATIVE ACKNOWLEDGE",
    "NAK",
    "SYNCHRONOUS IDLE",
    "SYN",
    "END OF TRANSMISSION BLOCK",
    "ETB",
    "CANCEL",
    "CAN",
    "END OF MEDIUM",
    "EOM",
    "EM",
    "SUBSTITUTE",
    "SUB",
    "ESCAPE",
    "ESC",
    "INFORMATION SEPARATOR FOUR",
    "FILE SEPARATOR",
    "FS",
    "INFORMATION SEPARATOR THREE",
    "GROUP SEPARATOR",
    "GS",
    "INFORMATION SEPARATOR TWO",
    "RECORD SEPARATOR",
    "RS",
    "INFORMATION SEPARATOR ONE",
    "UNIT SEPARATOR",
    "US",
    "SP",
    "DELETE",
    "DEL",
    "PADDING CHARACTER",
    "PAD",
    "HIGH OCTET PRESET",
    "HOP",
    "BREAK PERMITTED HERE",
    "BPH",
    "NO BREAK HERE",
    "NBH",
    "INDEX",
    "IND",
    "NEXT LINE",
    "NEL",
    "START OF SELECTED AREA",
    "SSA",
    "END OF SELECTED AREA",
    "ESA",
    "CHARACTER TABULATION SET",
    "HORIZONTAL TABULATION SET",
    "HTS",
    "CHARACTER TABULATION WITH JUSTIFICATION",
    "HORIZONTAL TABULATION WITH JUSTIFICATION",
    "HTJ",
    "LINE TABULATION SET",
    "VERTICAL TABULATION SET",
    "VTS",
    "PARTIAL LINE FORWARD",
    "PARTIAL LINE DOWN",
    "PLD",
    "PARTIAL LINE BACKWARD",
    "PARTIAL LINE UP",
    "PLU",
    "REVERSE LINE FEED",
    "REVERSE INDEX",
    "RI",
    "SINGLE SHIFT TWO",
    "SINGLE-SHIFT-2",
    "SS2",
    "SINGLE SHIFT THREE",
    "SINGLE-SHIFT-3",
    "SS3",
    "DEVICE CONTROL STRING",
    "DCS",
    "PRIVATE USE ONE",
    "PRIVATE USE-1",
    "PU1",
    "PRIVATE USE TWO",
    "PRIVATE USE-2",
    "PU2",
    "SET TRANSMIT STATE",
    "STS",
    "CANCEL CHARACTER",
    "CCH",
    "MESSAGE WAITING",
    "MW",
    "START OF GUARDED AREA",
    "START OF PROTECTED AREA",
    "SPA",
    "END OF GUARDED AREA",
    "END OF PROTECTED AREA",
    "EPA",
    "START OF STRING",
    "SOS",
    "SINGLE GRAPHIC CHARACTER INTRODUCER",
    "SGC",
    "SINGLE CHARACTER INTRODUCER",
    "SCI",
    "CONTROL SEQUENCE INTRODUCER",
    "CSI",
    "STRING TERMINATOR",
    "ST",
    "OPERATING SYSTEM COMMAND",
    "OSC",
    "PRIVACY MESSAGE",
    "PM",
    "APPLICATION PROGRAM COMMAND",
    "APC",
    "NBSP",
    "SHY",
    "LATIN CAPITAL LETTER GHA",
    "LATIN SMALL LETTER GHA",
    "CGJ",
    "ARABIC SMALL HIGH LIGATURE ALEF WITH YEH BARREE",
    "ALM",
    "SYRIAC SUBLINEAR COLON SKEWED LEFT",
    "KANNADA LETTER LLLA",
    "LAO LETTER FO FON",
    "LAO LETTER FO FAY",
    "LAO LETTER RO",
    "LAO LETTER LO",
    "TIBETAN MARK BKA- SHOG GI MGO RGYAN",
    "HANGUL JONGSEONG YESIEUNG-KIYEOK",
    "HANGUL JONGSEONG YESIEUNG-SSANGKIYEOK",
    "HANGUL JONGSEONG SSANGYESIEUNG",
    "HANGUL JONGSEONG YESIEUNG-KHIEUKH",
    "FVS1",
    "FVS2",
    "FVS3",
    "MVS",
    "FVS4",
    "SUNDANESE LETTER ARCHAIC I",
    "ZWSP",
    "ZWNJ",
    "ZWJ",
    "LRM",
    "RLM",
    "LRE",
    "RLE",
    "PDF",
    "LRO",
    "RLO",
    "NNBSP",
    "MMSP",
    "WJ",
    "LRI",
    "RLI",
    "FSI",
    "PDI",
    "WEIERSTRASS ELLIPTIC FUNCTION",
    "MICR ON US SYMBOL",
    "MICR DASH SYMBOL",
    "LEFTWARDS TRIANGLE-HEADED ARROW WITH DOUBLE VERTICAL STROKE",
    "RIGHTWARDS TRIANGLE-HEADED ARROW WITH DOUBLE VERTICAL STROKE",
    "YI SYLLABLE ITERATION MARK",
    "MYANMAR LETTER KHAMTI LLA",
    "VS1",
    "VS2",
    "VS3",
    "VS4",
    "VS5",
    "VS6",
    "VS7",
    "VS8",
    "VS9",
    "VS10",
    "VS11",
    "VS12",
    "VS13",
    "VS14",
    "VS15",
    "VS16",
    "PRESENTATION FORM FOR VERTICAL RIGHT WHITE LENTICULAR BRACKET",
    "BYTE ORDER MARK",
    "BOM",
    "ZWNBSP",
    "CUNEIFORM SIGN NU11 TENU",
    "CUNEIFORM SIGN NU11 OVER NU11 BUR OVER BUR",
    "MEDEFAIDRIN CAPITAL LETTER H",
    "MEDEFAIDRIN CAPITAL LETTER NG",
    "MEDEFAIDRIN SMALL LETTER H",
    "MEDEFAIDRIN SMALL LETTER NG",
    "HENTAIGANA LETTER E-1",
    "BYZANTINE MUSICAL SYMBOL FTHORA SKLIRON CHROMA VASIS",
    "VS17",
    "VS18",
    "VS19",
    "VS20",
    "VS21",
    "VS22",
    "VS23",
    "VS24",
    "VS25",
    "VS26",
    "VS27",
    "VS28",
    "VS29",
    "VS30",
    "VS31",
    "VS32",
    "VS33",
    "VS34",
    "VS35",
    "VS36",
    "VS37",
    "VS38",
    "VS39",
    "VS40",
    "VS41",
    "VS42",
    "VS43",
    "VS44",
    "VS45",
    "VS46",
    "VS47",
    "VS48",
    "VS49",
    "VS50",
    "VS51",
    "VS52",
    "VS53",
    "VS54",
    "VS55",
    "VS56",
    "VS57",
    "VS58",
    "VS59",
    "VS60",
    "VS61",
    "VS62",
    "VS63",
    "VS64",
    "VS65",
    "VS66",
    "VS67",
    "VS68",
    "VS69",
    "VS70",
    "VS71",
    "VS72",
    "VS73",
    "VS74",
    "VS75",
    "VS76",
    "VS77",
    "VS78",
    "VS79",
    "VS80",
    "VS81",
    "VS82",
    "VS83",
    "VS84",
    "VS85",
    "VS86",
    "VS87",
    "VS88",
    "VS89",
    "VS90",
    "VS91",
    "VS92",
    "VS93",
    "VS94",
    "VS95",
    "VS96",
    "VS97",
    "VS98",
    "VS99",
    "VS100",
    "VS101",
    "VS102",
    "VS103",
    "VS104",
    "VS105",
    "VS106",
    "VS107",
    "VS108",
    "VS109",
    "VS110",
    "VS111",
    "VS112",
    "VS113",
    "VS114",
    "VS115",
    "VS116",
    "VS117",
    "VS118",
    "VS119",
    "VS120",
    "VS121",
    "VS122",
    "VS123",
    "VS124",
    "VS125",
    "VS126",
    "VS127",
    "VS128",
    "VS129",
    "VS130",
    "VS131",
    "VS132",
    "VS133",
    "VS134",
    "VS135",
    "VS136",
    "VS137",
    "VS138",
    "VS139",
    "VS140",
    "VS141",
    "VS142",
    "VS143",
    "VS144",
    "VS145",
    "VS146",
    "VS147",
    "VS148",
    "VS149",
    "VS150",
    "VS151",
    "VS152",
    "VS153",
    "VS154",
    "VS155",
    "VS156",
    "VS157",
    "VS158",
    "VS159",
    "VS160",
    "VS161",
    "VS162",
    "VS163",
    "VS164",
    "VS165",
    "VS166",
    "VS167",
    "VS168",
    "VS169",
    "VS170",
    "VS171",
    "VS172",
    "VS173",
    "VS174",
    "VS175",
    "VS176",
    "VS177",
    "VS178",
    "VS179",
    "VS180",
    "VS181",
    "VS182",
    "VS183",
    "VS184",
    "VS185",
    "VS186",
    "VS187",
    "VS188",
    "VS189",
    "VS190",
    "VS191",
    "VS192",
    "VS193",
    "VS194",
    "VS195",
    "VS196",
    "VS197",
    "VS198",
    "VS199",
    "VS200",
    "VS201",
    "VS202",
    "VS203",
    "VS204",
    "VS205",
    "VS206",
    "VS207",
    "VS208",
    "VS209",
    "VS210",
    "VS211",
    "VS212",
    "VS213",
    "VS214",
    "VS215",
    "VS216",
    "VS217",
    "VS218",
    "VS219",
    "VS220",
    "VS221",
    "VS222",
    "VS223",
    "VS224",
    "VS225",
    "VS226",
    "VS227",
    "VS228",
    "VS229",
    "VS230",
    "VS231",
    "VS232",
    "VS233",
    "VS234",
    "VS235",
    "VS236",
    "VS237",
    "VS238",
    "VS239",
    "VS240",
    "VS241",
    "VS242",
    "VS243",
    "VS244",
    "VS245",
    "VS246",
    "VS247",
    "VS248",
    "VS249",
    "VS250",
    "VS251",
    "VS252",
    "VS253",
    "VS254",
    "VS255",
    "VS256",
)


def fnv64(text):
    h = 0xCBF29CE484222325
    for byte in text.encode("ascii"):
        h = ((h ^ byte) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def name_hashes():
    """FNV-1a hashes of every name re's \\N{...} takes (what unicodedata.name
    gives, each checked to look up again), but the two kinds CPython works
    out by rule instead: Hangul syllables and CJK unified ideographs."""
    found = {}
    for c in range(0x110000):
        name = unicodedata.name(chr(c), None)
        if name is None or name.startswith(
            ("HANGUL SYLLABLE ", "CJK UNIFIED IDEOGRAPH-")
        ):
            continue
        found[fnv64(name)] = c
        if unicodedata.lookup(name) != chr(c):
            raise SystemExit(f"{name}: lookup does not take it back")
    for alias in ALIASES:
        if len(unicodedata.lookup(alias)) != 1:
            raise SystemExit(f"{alias}: not one character")
        found[fnv64(alias)] = ord(unicodedata.lookup(alias))
    hexes = [f"{h:016x}{found[h]:06x}" for h in sorted(found)]
    lines = [
        "/// FNV-1a hashes of the names and aliases unicodedata.lookup takes, sorted,",
        "/// sixteen hex digits each, then the six of the character it names.",
        "pub static NAME_HASHES: &str = concat!(",
    ]
    for i in range(0, len(hexes), 8):
        lines.append(f'    "{"".join(hexes[i : i + 8])}",')
    lines.append(");")
    return "\n".join(lines)


def render():
    word = re.compile(r"\w")
    space = re.compile(r"\s")
    digit = re.compile(r"\d")
    spaces = ranges(lambda c: chr(c).isspace())
    if spaces != ranges(lambda c: bool(space.match(chr(c)))):
        raise SystemExit(
            "str.isspace and re's \\s disagree; the port assumes they agree"
        )
    decimals = ranges(lambda c: chr(c).isdecimal())
    if decimals != ranges(lambda c: bool(digit.match(chr(c)))):
        raise SystemExit(
            "str.isdecimal and re's \\d disagree; the port assumes they agree"
        )
    parts = [
        HERE_LICENSE.replace("#!/usr/bin/env python3\n", "")
        .replace("# ", "// ")
        .replace("#\n", "//\n")
        .rstrip(),
        "",
        "// GENERATED by tools/sdk-codegen/gen_unicode_tables.py from Python "
        f"{sys.version_info.major}.{sys.version_info.minor}, Unicode "
        f"{unicodedata.unidata_version}. Do not edit by hand.",
        "",
        table("SPACE", spaces, "str.isspace(), which is also re's \\s."),
        "",
        table("WORD", ranges(lambda c: bool(word.match(chr(c)))), "re's \\w on a str."),
        "",
        table("DECIMAL", decimals, "str.isdecimal(), which is also re's \\d."),
        "",
        table("DIGIT", ranges(lambda c: chr(c).isdigit()), "str.isdigit()."),
        "",
        table(
            "ALPHA",
            ranges(lambda c: chr(c).isalpha()),
            "str.isalpha() of one character.",
        ),
        "",
        table(
            "UPPER",
            ranges(lambda c: chr(c).isupper()),
            "str.isupper() of one character.",
        ),
        "",
        table(
            "LOWER",
            ranges(lambda c: chr(c).islower()),
            "str.islower() of one character.",
        ),
        "",
        table(
            "PRINTABLE",
            ranges(lambda c: chr(c).isprintable()),
            "str.isprintable(), which decides what repr() escapes.",
        ),
        "",
        table(
            "ID_START",
            ranges(lambda c: chr(c).isidentifier()),
            "Characters str.isidentifier() takes first.",
        ),
        "",
        table(
            "ID_CONTINUE",
            ranges(lambda c: ("a" + chr(c)).isidentifier()),
            "Characters str.isidentifier() takes after the first.",
        ),
        "",
        table(
            "CASED",
            ranges(lambda c: (chr(c) + "\u03a3").lower()[-1] == "\u03c2"),
            "Cased characters that are not case-ignorable, as lower()'s final sigma rule sees them.",
        ),
        "",
        table(
            "CASE_IGNORABLE",
            ranges(
                lambda c: (
                    ("A" + chr(c) + "\u03a3").lower()[-1] == "\u03c2"
                    and (chr(c) + "\u03a3").lower()[-1] != "\u03c2"
                )
            ),
            "Case-ignorable characters, which lower()'s final sigma rule looks past.",
        ),
        "",
        table(
            "CJK_UNIFIED",
            ranges(
                lambda c: unicodedata.name(chr(c), "").startswith(
                    "CJK UNIFIED IDEOGRAPH-"
                )
            ),
            "CJK unified ideographs, whose names CPython works out.",
        ),
        "",
        name_hashes(),
        "",
        mapping(
            "LOWER_MAP", str.lower, "str.lower() of one character, where it changes it."
        ),
        "",
        mapping(
            "UPPER_MAP", str.upper, "str.upper() of one character, where it changes it."
        ),
        "",
        mapping(
            "TITLE_MAP",
            lambda c: c.capitalize(),
            "str.capitalize() of one character (its title case), where it changes it.",
        ),
        "",
    ]
    return "\n".join(parts)


if __name__ == "__main__":
    sys.stdout.write(render())
