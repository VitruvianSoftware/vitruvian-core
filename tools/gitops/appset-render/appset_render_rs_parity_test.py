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

"""appset-render, the Rust port, against the Go original: same exit code,
stdout and stderr, byte for byte, on every input here.

    bazel test //tools/gitops/appset-render:appset_render_rs_parity_test

The Go tool parses with Go's own text/template, so this is also the check
that src/parse.rs agrees with the parser ArgoCD uses. The inputs:
  * the repository's real gitops/argocd tree, with and without the disabled
    appsets (found through main.go's runfile symlink, as lint-naming's
    parity test finds the tree; skipped only where a sandbox hides it);
  * every scenario in main_test.go, as files;
  * a corpus of template edge cases, one file each: delimiters and trim
    markers, comments, every control structure and its misuse, variables
    and declarations, numbers of every syntax (and the strconv/Sscan corner
    cases), strings and character constants, Unicode and invalid UTF-8,
    nesting near the 10000-deep limit, {{define}}/{{block}} redefinition;
  * seeded random mutations of the real appsets and random token soup
    (APPSET_PARITY_FUZZ=<n> and APPSET_PARITY_SEED=<s> for a local soak);
  * file names that Go's fmt reads as verbs (Go builds its error format
    with the file name inside it), and ones with spaces and invalid UTF-8;
  * flags (-h, unknown, malformed, bool values, missing arguments), the
    workspace directory, missing, empty and unreadable roots, symlinks.
"""

import os
import random
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GO = os.environ.get("APPSET_RENDER_GO", "")
RS = os.environ.get("APPSET_RENDER_RS", "")
FUZZ = int(os.environ.get("APPSET_PARITY_FUZZ", "1500"))
SEED = int(os.environ.get("APPSET_PARITY_SEED", "414"))


def _bin(path):
    if not path:
        raise unittest.SkipTest("run this under bazel test")
    return os.path.abspath(path)


def repo_root():
    p = os.path.realpath(os.path.join(HERE, "main.go"))
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(p))))
    if os.path.isdir(os.path.join(root, "gitops", "argocd")) and os.path.exists(
        os.path.join(root, "MODULE.bazel")
    ):
        return root
    return None


def real_appsets():
    root = repo_root()
    if root is None:
        return []
    out = []
    for d, _, files in os.walk(os.path.join(root, "gitops", "argocd")):
        for f in sorted(files):
            if f.startswith("applicationset"):
                with open(os.path.join(d, f), "rb") as fh:
                    out.append(fh.read())
    return out


# Template edge cases. Each becomes its own applicationset file.
CORPUS = [
    b"",
    b"plain text, no actions\n",
    b"{{",
    b"}}",
    b"{{}}",
    b"{{ }}",
    b"{{-}}",
    b"{{- -}}",
    b"a {{- .x -}} b",
    b"a {{-.x}}",
    b"{{.x-}}",
    b"{{ .x -}}\n\n b",
    b"\n\n  {{- .x}}",
    b"{{.x}}",
    b"{{ .x.y.z }}",
    b"{{.}}",
    b"{{..}}",
    b"{{ . }}",
    b"{{.x.}}",
    b"{{ .x .y }}",
    b"{{/* c */}}",
    b"{{- /* c */ -}}",
    b"{{/* c */ }}",
    b"{{/* c",
    b"{{/**/}}",
    b"{{ /* c */ }}",
    b"{{/* a\nb\nc */}}\n{{ .x",
    b"{{- /* c */}}x",
    b"{{if .x}}a{{end}}",
    b"{{if .x}}a{{else}}b{{end}}",
    b"{{if .x}}a{{else if .y}}b{{else}}c{{end}}",
    b"{{if .x}}a{{else with .y}}b{{end}}",
    b"{{with .x}}a{{else with .y}}b{{else}}c{{end}}",
    b"{{with .x}}a{{else if .y}}b{{end}}",
    b"{{if}}x{{end}}",
    b"{{if .x}}",
    b"{{if .x}}{{else}}",
    b"{{if .x}}a{{else}}b{{else}}c{{end}}",
    b"{{end}}",
    b"{{else}}",
    b"{{ end x }}",
    b"{{ else x }}",
    b"{{range .x}}{{.}}{{end}}",
    b"{{range $i, $v := .x}}{{$i}}{{$v}}{{end}}",
    b"{{range $i, $v, $w := .x}}{{end}}",
    b"{{range $i, 3 := .x}}{{end}}",
    b"{{range $i, }}{{end}}",
    b"{{range $i := .x}}{{break}}{{continue}}{{end}}",
    b"{{break}}",
    b"{{continue}}",
    b"{{range .x}}{{break 1}}{{end}}",
    b"{{range .x}}{{if .y}}{{break}}{{end}}{{end}}",
    b"{{range .x}}{{else}}none{{end}}",
    b"{{ $x := 1 }}{{ $x }}",
    b"{{ $x = 1 }}",
    b"{{ $x }}",
    b"{{ $ }}",
    b"{{ $.x }}",
    b"{{ $x := 1 }}{{ $x.y }}",
    b"{{ $x, $y := .a }}",
    b"{{ $x := }}",
    b'{{ $x := .a | printf "%s" }}',
    b"{{ $x:=1}}",
    b"{{ $x :1 }}",
    b"{{ $x : = 1 }}",
    b"{{with $x := .a}}{{$x}}{{end}}{{$x}}",
    b"{{if $x := .a}}{{end}}",
    b'{{define "a"}}x{{end}}',
    b'{{define "a"}}x{{end}}{{define "a"}}y{{end}}',
    b'{{define "a"}} {{end}}{{define "a"}}y{{end}}',
    b'{{define "applicationset.yaml"}}x{{end}}body',
    b'{{define "applicationset.yaml"}}x{{end}}  ',
    b"{{define a}}x{{end}}",
    b'{{define "a" .x}}{{end}}',
    b'{{define "a"}}{{else}}{{end}}',
    b'{{define "a"}}x',
    b"{{define `raw`}}{{end}}",
    b'{{define "\\q"}}{{end}}',
    b'{{define "a"}}{{define "b"}}{{end}}{{end}}',
    b'{{block "b" .}}x{{end}}',
    b'{{block "b" .}}x{{else}}{{end}}',
    b"{{block b .}}{{end}}",
    b'{{block "b"}}{{end}}',
    b'{{template "a"}}',
    b'{{template "a" .x}}',
    b"{{template a}}",
    b'{{template "a" .x .y}}',
    b"{{ template }}",
    b"{{ 1 }}",
    b"{{ -1 }}",
    b"{{ +1 }}",
    b"{{ 1.5 }}",
    b"{{ .5 }}",
    b"{{ 1. }}",
    b"{{ 1e3 }}",
    b"{{ 1e }}",
    b"{{ 1e+ }}",
    b"{{ 1E-5 }}",
    b"{{ 0x1F }}",
    b"{{ 0X1f }}",
    b"{{ 0x }}",
    b"{{ 0xg }}",
    b"{{ 0o17 }}",
    b"{{ 0O8 }}",
    b"{{ 0b101 }}",
    b"{{ 0b2 }}",
    b"{{ 017 }}",
    b"{{ 08 }}",
    b"{{ 09.5 }}",
    b"{{ 1_000 }}",
    b"{{ 1__0 }}",
    b"{{ _1 }}",
    b"{{ 1_ }}",
    b"{{ 0x_1 }}",
    b"{{ 0_7 }}",
    b"{{ 1_0.5 }}",
    b"{{ 0x1p3 }}",
    b"{{ 0x1.8p1 }}",
    b"{{ 0x1.8 }}",
    b"{{ 0x1p }}",
    b"{{ 0x1p-1074 }}",
    b"{{ 0x1p1024 }}",
    b"{{ 0x1.fffffffffffffp1023 }}",
    b"{{ 0x1.fffffffffffff8p1023 }}",
    b"{{ 1e308 }}",
    b"{{ 1e309 }}",
    b"{{ 1.7976931348623157e308 }}",
    b"{{ 1.7976931348623159e308 }}",
    b"{{ 1e-400 }}",
    b"{{ 18446744073709551615 }}",
    b"{{ 18446744073709551616 }}",
    b"{{ 9223372036854775807 }}",
    b"{{ -9223372036854775808 }}",
    b"{{ -9223372036854775809 }}",
    b"{{ 99999999999999999999 }}",
    b"{{ 0xFFFFFFFFFFFFFFFFFF }}",
    b"{{ -0 }}",
    b"{{ 1i }}",
    b"{{ 1.5i }}",
    b"{{ +i }}",
    b"{{ i }}",
    b"{{ 1+2i }}",
    b"{{ 1-2i }}",
    b"{{ 1+i }}",
    b"{{ 1+2 }}",
    b"{{ 1+2j }}",
    b"{{ 1e3+1e3i }}",
    b"{{ 0x1p2+0x1p3i }}",
    b"{{ 0X1p2+1i }}",
    b"{{ 0X1P2+1i }}",
    b"{{ 1+0X1p1i }}",
    b"{{ 1_+2i }}",
    b"{{ 1+2_i }}",
    b"{{ 1e400+1i }}",
    b"{{ .5+.5i }}",
    b"{{ 1+2i3 }}",
    b"{{ 1x }}",
    b"{{ 1.2.3 }}",
    b"{{ 1..2 }}",
    b"{{ 3.x }}",
    b"{{ 1 .x }}",
    b"{{ 'a' }}",
    b"{{ '\\n' }}",
    b"{{ '\\x41' }}",
    b"{{ '\\u00e9' }}",
    b"{{ '\\U0001F600' }}",
    b"{{ '\\777' }}",
    b"{{ '\\400' }}",
    b"{{ '\\377' }}",
    b"{{ 'ab' }}",
    b"{{ '' }}",
    b"{{ '\\q' }}",
    b"{{ '\\'' }}",
    b"{{ '\"' }}",
    b"{{ '\\\"' }}",
    b"{{ '",
    b"{{ 'a",
    b"{{ '\n' }}",
    b"{{ '\\uD800' }}",
    "{{ '\u00e9' }}".encode(),
    b"{{ '\xff' }}",
    b"{{ '\\x4' }}",
    b'{{ "a" }}',
    b'{{ "a\\tb" }}',
    b'{{ "\\q" }}',
    b'{{ "\\\'" }}',
    b'{{ "a\n" }}',
    b'{{ "a',
    b'{{ "\\" }}',
    b"{{ `raw` }}",
    b"{{ `raw\nwith newline` }}",
    b"{{ `a\r\nb` }}",
    b"{{ `a",
    b'{{ "\xff" }}',
    '{{ "\u00e9" }}'.encode(),
    b'{{ "abcdefghijklmnop" | }}',
    b'{{ .x "abcdefghijklmnop" ! }}',
    b'{{ "abcdefghijk".x }}',
    b"{{ `abcdefghijkl`.x }}",
    b"{{ true }}",
    b"{{ false }}",
    b"{{ true.x }}",
    b"{{ nil }}",
    b"{{ nil.x }}",
    b"{{ .x | nil }}",
    b"{{ .x | true }}",
    b"{{ .x | 3 }}",
    b'{{ .x | "s" }}',
    b"{{ .x | . }}",
    b"{{ .x | .y }}",
    b"{{ .x | quote | upper }}",
    b"{{ quote }}",
    b"{{ nosuch }}",
    b"{{ .x | nosuch }}",
    b"{{ break }}",
    b'{{ printf "%d" 1 }}',
    b"{{ (1) }}",
    b"{{ (.x).y }}",
    b"{{ (.x | quote).y }}",
    b"{{ ( }}",
    b"{{ ) }}",
    b"{{ (.x }}",
    b"{{ .x) }}",
    b"{{ () }}",
    b"{{ (()) }}",
    b"{{ .x ( .y ) }}",
    b"{{ .x = 1 }}",
    b"{{ .x := 1 }}",
    b"{{ | }}",
    b"{{ .x | }}",
    b"{{ .x || .y }}",
    b"{{ , }}",
    b"{{ .x, .y }}",
    b"{{ ! }}",
    b"{{ # }}",
    b"{{ @ }}",
    b"{{ ~ }}",
    b"{{ ^ }}",
    b"{{ ; }}",
    "{{ \u20ac }}".encode(),
    "{{ .\u00e9t\u00e9 }}".encode(),
    "{{ $\u00e9 := 1 }}{{ $\u00e9 }}".encode(),
    "{{ .x\u00a0}}".encode(),
    "{{ .x\u3000}}".encode(),
    b"{{ .x\xff }}",
    b"{{ \xff }}",
    b"{{ .\xff }}",
    b"{{ .x\x00 }}",
    b"{{ \x01 }}",
    b"{{ .x\t}}",
    b"{{\t.x\r\n}}",
    b"{{ .x\x7f }}",
    b"{{ .a-b }}",
    b"{{ .a+b }}",
    b"{{ .a*b }}",
    b"{{ .a/b }}",
    b"{{ $a-b }}",
    b"{{ a-b }}",
    "{{ \u0663 }}".encode(),
    "{{ .x\u0663 }}".encode(),
    "{{ \u01c5x }}".encode(),
    b"{{`\nok {{ $labels }}\n`}}",
    b"{{`\nbad `x`\n`}}",
    b"{{` unterminated",
    b"{{ ` }}",
    b"line1\nline2\n{{ .x\nline4 }}",
    b"a\n{{if .x}}\nb\n{{else}}\nc\n{{end}}\n{{end}}",
    b"\n\n{{ (\n\n.x\n\n }}",
    b"{{ .x\n| quote\n| upper }}",
    b"{{\n\n.x\n\n",
    b"{{ $x := 1\n}}{{\n$y }}",
    b"{{ {{ }} }}",
    b"{{{ .x }}}",
    b"{{ .x }}}}",
    b"{{{{ .x }}",
    b"{{-",
    b"{{- ",
    b"x {{- ",
    b" -}}",
    b"{{ .x -}",
    b"{{ .x - }}",
    b"{{ .x -}}}",
    b"{{- -}}{{- -}}",
    b"{{ -1 -}}",
    b"{{ - }}",
]


class Parity(unittest.TestCase):
    def setUp(self):
        self.go = _bin(GO)
        self.rs = _bin(RS)
        self.tmp = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
        self.n = 0

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_both(self, args, cwd=None, env=None, argv0=b"appset-render"):
        res = []
        e = {"PATH": "/usr/bin:/bin"}
        e.update(env or {})
        for b in (self.go, self.rs):
            p = subprocess.run(
                [argv0, *args],
                executable=b,
                cwd=cwd or self.tmp,
                env=e,
                capture_output=True,
            )
            res.append((p.returncode, p.stdout, p.stderr))
        return res

    def same(self, args, want_code=None, **kw):
        go, rs = self.run_both(args, **kw)
        if go != rs:
            self.fail(
                "args=%r\n--- go (%d)\n%s%s\n--- rs (%d)\n%s%s"
                % (
                    args,
                    go[0],
                    go[1].decode("utf-8", "replace"),
                    go[2].decode("utf-8", "replace"),
                    rs[0],
                    rs[1].decode("utf-8", "replace"),
                    rs[2].decode("utf-8", "replace"),
                )
            )
        if want_code is not None:
            self.assertEqual(go[0], want_code, go)
        return go

    def tree(self, files):
        """A fresh root holding {relative name (bytes): content (bytes)}."""
        self.n += 1
        root = os.path.join(os.fsencode(self.tmp), b"t%d" % self.n)
        for name, content in files.items():
            p = os.path.join(root, name)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as f:
                f.write(content)
        return root

    def same_tree(self, files, args=()):
        """same() on a fresh tree, unless the filesystem refuses a name
        (macOS rejects file names that are not valid UTF-8)."""

        def utf8(b):
            try:
                b.decode("utf-8")
                return True
            except UnicodeDecodeError:
                return False

        try:
            root = self.tree(files)
        except OSError:
            if all(utf8(n) for n in files):
                raise
            return None
        return self.same([b"-root", root, *args])

    def batch(self, sources, name_fmt=b"applicationset-%05d.yaml"):
        """Every source as its own file under one root, compared in chunks."""
        for start in range(0, len(sources), 400):
            chunk = sources[start : start + 400]
            root = self.tree({name_fmt % (start + i): s for i, s in enumerate(chunk)})
            self.same([b"-root", root])

    # --- the real tree ------------------------------------------------------

    def test_the_real_gitops_tree(self):
        root = repo_root()
        if root is None:
            self.skipTest("the source tree is not visible from this sandbox")
        r = self.same([b"-root", b"gitops/argocd"], 0, cwd=root)
        self.assertIn(b"render-parse clean", r[1])
        self.same([b"-root", b"gitops/argocd", b"-include-disabled=false"], 0, cwd=root)
        self.same([], 0, cwd=root)
        self.same([], 0, env={"BUILD_WORKSPACE_DIRECTORY": root})
        self.same(
            [b"-root", os.path.join(root, "gitops", "argocd", "platform").encode()], 0
        )

    # --- main_test.go -------------------------------------------------------

    def test_main_test_scenarios(self):
        cases = [
            b"spec:\n  template:\n    values: |\n      {{`\n      annotations:\n        summary: pod `oops` restarting\n      `}}\n",
            b"spec:\n  template:\n    values: |\n      {{`\n      annotations:\n        summary: {{ $labels.namespace }} restarting\n      `}}\n",
            b"spec:\n  template:\n    values: |\n      summary: {{ $labels.namespace }}\n",
            b"spec:\n  template:\n    spec:\n      destination:\n        server: '{{.server}}'\n        name: '{{.name}}'\n",
            b"spec:\n  template:\n    v: {{ .values | nindent 12 }}\n",
            b"spec:\n  template:\n    v: {{ .name | quote }}\n",
            b"spec:\n  template:\n    v: {{ .cfg | toYaml | indent 4 }}\n",
            b'spec:\n  template:\n    v: {{ default "x" .missing }}\n',
            b"spec:\n  template:\n    v: {{ .server \n",
            b"v: |\n  {{`\n  a `x`\n  `}}\n",
            b"v: {{ $labels.ns }}\n",
        ]
        for c in cases:
            self.same([b"-root", self.tree({b"applicationset.yaml": c})])
            self.same(
                [
                    b"-root",
                    self.tree(
                        {
                            b"applicationset.yaml.disabled": c,
                            b"applicationset.yaml": b"ok",
                        }
                    ),
                ]
            )

    # --- corpus -------------------------------------------------------------

    def test_corpus(self):
        self.batch(CORPUS)
        # Each case once more inside surrounding text, and as a disabled file.
        self.batch([b"head\n  " + c + b"\n tail {{ .ok }}\n" for c in CORPUS])
        self.batch(CORPUS, name_fmt=b"applicationset-%05d.yaml.disabled")

    def test_nesting_depth(self):
        for depth in (9999, 10000, 10001):
            self.same(
                [
                    b"-root",
                    self.tree(
                        {
                            b"applicationset.yaml": b"{{ "
                            + b"(" * depth
                            + b"1"
                            + b")" * depth
                            + b" }}"
                        }
                    ),
                ]
            )
        nested = b"{{if .a}}" * 2000 + b"x" + b"{{end}}" * 2000
        self.same([b"-root", self.tree({b"applicationset.yaml": nested})])
        self.same([b"-root", self.tree({b"applicationset.yaml": nested[:-7]})])

    def test_fuzz(self):
        rng = random.Random(SEED)
        seeds = real_appsets() or [c for c in CORPUS if c]
        atoms = [
            b"{{",
            b"}}",
            b"{{-",
            b"-}}",
            b" ",
            b"\n",
            b"`",
            b'"',
            b"'",
            b"\\",
            b"$",
            b".",
            b"|",
            b"(",
            b")",
            b",",
            b":=",
            b"=",
            b"-",
            b"+",
            b"if",
            b"else",
            b"end",
            b"range",
            b"with",
            b"define",
            b"block",
            b"template",
            b"break",
            b"continue",
            b"nil",
            b"true",
            b"/*",
            b"*/",
            b"quote",
            b"nindent",
            b"x",
            b"$x",
            b".x",
            b"1",
            b"0x",
            b"1e",
            b"i",
            b"_",
            b"\xff",
            "\u00e9".encode(),
            b"\t",
            b"\r",
            b"#",
            b"{{`",
            b"`}}",
            b"{{ $labels }}",
            b"p",
            b"8",
        ]
        sources = []
        for _ in range(FUZZ):
            kind = rng.random()
            if kind < 0.6:
                s = bytearray(rng.choice(seeds))
                for _ in range(rng.randint(1, 4)):
                    op = rng.random()
                    pos = rng.randint(0, len(s))
                    if op < 0.4:
                        s[pos:pos] = rng.choice(atoms)
                    elif op < 0.7 and s:
                        del s[pos : pos + rng.randint(1, 3)]
                    elif op < 0.85 and s:
                        s = s[:pos]
                    else:
                        a, b = sorted((rng.randint(0, len(s)), rng.randint(0, len(s))))
                        s[a:b] = s[a:b][::-1]
                sources.append(bytes(s))
            else:
                sources.append(
                    b"".join(rng.choice(atoms) for _ in range(rng.randint(1, 25)))
                )
        self.batch(sources)

    # --- names, flags, paths -------------------------------------------------

    def test_file_names_with_fmt_verbs(self):
        bad = b"{{end}}"  # an error that prints a node
        bad2 = b"{{ .x ! }}"  # an error that prints an item and a string
        bad3 = b"{{ 'ab' }}"  # an error that prints an error value
        bad4 = b"{{ 1+i_ }}"  # Sscan's *strconv.NumError
        bad5 = b"{{ .x | 3 }}"  # an int argument
        names = [
            b"%s",
            b"%d",
            b"%v",
            b"%q",
            b"%x",
            b"%X",
            b"%%",
            b"%",
            b"%!",
            b"%5s",
            b"%-5d",
            b"%.2s",
            b"%+v",
            b"%#v",
            b"%T",
            b"%w",
            b"%c",
            b"%U",
            b"%#U",
            b"%[2]s",
            b"%[1]d%[1]q",
            b"%[9]s",
            b"%*d",
            b"%.*s",
            b"%s%s%s%s",
            b"%e",
            b"%o",
            b"%#x",
            b"%08d",
            b"% d",
            b"%[x]s",
            b"%\xff",
            b"%[2]*[1]d",
            b"%-08s",
            b"%.0d",
            b"%[1]",
            b"%.",
            b"%3.1q",
            b"%b",
            b"%O",
            b"%t",
            b"%+d",
            b"%+q",
            b"% +d",
            b"%+x",
            b"%#q",
            b"%#o",
            b"%#b",
            b"%-+5d",
            b"%x%X",
        ]
        for n in names:
            for content in (bad2, bad3, bad5):
                self.same_tree({b"applicationset" + n + b".yaml": content})
        # A parse node is a pointer: under a verb its String method does not
        # handle, Go prints a field's address, which differs between runs of
        # the Go tool itself. Only the verbs that print deterministically.
        for n in (
            b"%s",
            b"%v",
            b"%q",
            b"%x",
            b"%X",
            b"%T",
            b"%%",
            b"%5s",
            b"%-9q",
            b"%.3s",
            b"%[1]s",
            b"%[2]s",
            b"%s%s",
            b"%%s",
        ):
            self.same_tree({b"applicationset" + n + b".yaml": bad})
        for n in (b"%s", b"%q", b"%x", b"%v", b"%T", b"%w", b"%+v"):
            self.same_tree({b"applicationset" + n + b".yaml": bad4})
        for n in (
            b" with space",
            b"-\xff\xfe",
            "-\u00e9".encode(),
            b".yaml.disabled",
            b"\n",
        ):
            self.same_tree({b"applicationset" + n: bad2})

    def test_flags(self):
        root = self.tree(
            {
                b"applicationset.yaml": b"{{ .x }}",
                b"x/applicationset.yaml.disabled": b"{{ end }}",
            }
        )
        for args in (
            [],
            [b"-h"],
            [b"-help"],
            [b"--help"],
            [b"-root"],
            [b"--root"],
            [b"-root", root],
            [b"--root", root],
            [b"-root=" + root],
            [b"--root=" + root],
            [b"-root", root, b"-root", b"/nonexistent"],
            [b"-nope"],
            [b"-x=1"],
            [b"---root"],
            [b"-=x"],
            [b"--=x"],
            [b"--"],
            [b"-"],
            [b"--", b"-nope"],
            [b"stray", b"-nope"],
            [b"-root", root, b"stray", b"-nope"],
            [b"-root", root, b"-include-disabled"],
            [b"-root", root, b"-include-disabled=false"],
            [b"-root", root, b"-include-disabled=0"],
            [b"-root", root, b"-include-disabled=F"],
            [b"-root", root, b"-include-disabled=FALSE"],
            [b"-root", root, b"-include-disabled=False"],
            [b"-root", root, b"-include-disabled=true"],
            [b"-root", root, b"-include-disabled=maybe"],
            [b"-root", root, b"-include-disabled="],
            [b"-root", root, b'-include-disabled=\xff"'],
            [b"-root", root, b"-include-disabled", b"false"],
            [b"-include-disabled=false", b"-root", root],
            [b"-root", b"-include-disabled"],
            [b"-h", b"-nope"],
            [b"-nope", b"-h"],
            [b"-ROOT", root],
            [b"-root=", b"x"],
        ):
            self.same(args)
        self.same([b"-h"], argv0=b"/some/path/appset-render")
        self.same([b"-nope"], argv0=b"\xffodd name")

    def test_paths(self):
        empty = os.path.join(os.fsencode(self.tmp), b"empty")
        os.makedirs(empty)
        self.same([b"-root", empty], 1)
        self.same([b"-root", b"/nonexistent/root"], 1)
        self.same([b"-root", b""], 1)
        only_disabled = self.tree({b"applicationset.yaml.disabled": b"{{ .x }}"})
        self.same([b"-root", only_disabled, b"-include-disabled=false"], 1)
        self.same([b"-root", only_disabled], 0)
        bad_disabled = self.tree(
            {
                b"applicationset.yaml.disabled": b"{{ end }}",
                b"applicationset.yaml": b"x",
            }
        )
        self.same([b"-root", bad_disabled], 0)
        # Not applicationset files, and names that only look similar.
        mixed = self.tree(
            {
                b"values.yaml": b"{{ end }}",
                b"Applicationset.yaml": b"{{ end }}",
                b"a/applicationset": b"{{ .x }}",
                b"b/applicationsets.yaml": b"{{ .y }}",
                b"c/xapplicationset.yaml": b"{{ end }}",
                b"d/e/f/applicationset-deep.yaml": b"{{ .z }}",
                b"applicationset.yml": b"{{ $x }}",
            }
        )
        self.same([b"-root", mixed], 1)
        # The root given as a file, with odd spellings, and via symlinks.
        single = self.tree(
            {
                b"applicationset.yaml": b"{{ .x }}",
                b"applicationset-2.yaml": b"{{ $bad }}",
            }
        )
        self.same([b"-root", os.path.join(single, b"applicationset.yaml")], 0)
        self.same([b"-root", os.path.join(single, b"applicationset-2.yaml")], 1)
        self.same([b"-root", os.path.join(single, b"applicationset.yaml/")], 1)
        self.same([b"-root", single + b"//./"], 1)
        self.same([b"-root", single + b"/../" + os.path.basename(single)], 1)
        link = os.path.join(os.fsencode(self.tmp), b"link")
        os.symlink(single, link)
        self.same([b"-root", link], 1)
        self.same([b"-root", link + b"/"], 1)
        inner = self.tree({b"applicationset.yaml": b"ok"})
        os.symlink(single, os.path.join(inner, b"sub"))
        os.symlink(
            os.path.join(single, b"applicationset-2.yaml"),
            os.path.join(inner, b"applicationset-link.yaml"),
        )
        os.symlink(single, os.path.join(inner, b"applicationset-dirlink"))
        os.symlink(b"/nonexistent", os.path.join(inner, b"applicationset-dangling"))
        self.same([b"-root", inner], 1)
        # Relative roots, from a working directory and from the workspace.
        self.same([b"-root", os.path.basename(single)], 1, cwd=os.path.dirname(single))
        self.same(
            [b"-root", os.path.basename(single)],
            1,
            env={"BUILD_WORKSPACE_DIRECTORY": os.path.dirname(single)},
        )
        self.same([], 1, env={"BUILD_WORKSPACE_DIRECTORY": "/nonexistent/ws"})
        self.same([b"-h"], 0, env={"BUILD_WORKSPACE_DIRECTORY": "/nonexistent/ws"})
        self.same([b"-root", single], 1, env={"BUILD_WORKSPACE_DIRECTORY": ""})
        if os.geteuid() != 0:
            locked = self.tree(
                {b"applicationset.yaml": b"x", b"sub/applicationset.yaml": b"y"}
            )
            os.chmod(os.path.join(locked, b"applicationset.yaml"), 0)
            self.same([b"-root", locked], 1)
            os.chmod(os.path.join(locked, b"sub"), 0)
            try:
                self.same([b"-root", locked], 1)
            finally:
                os.chmod(os.path.join(locked, b"sub"), 0o755)
                os.chmod(os.path.join(locked, b"applicationset.yaml"), 0o644)


class Harness(unittest.TestCase):
    """The comparison is not vacuous: different files give different output."""

    def test_outputs_differ_when_inputs_do(self):
        p = Parity("test_corpus")
        p.setUp()
        try:
            a = subprocess.run(
                [p.go, b"-root", p.tree({b"applicationset.yaml": b"{{ $a }}"})],
                capture_output=True,
            )
            b = subprocess.run(
                [p.rs, b"-root", p.tree({b"applicationset.yaml": b"{{ $b }}"})],
                capture_output=True,
            )
            self.assertEqual(a.returncode, b.returncode)
            self.assertNotEqual(a.stderr, b.stderr)
        finally:
            p.tearDown()


if __name__ == "__main__":
    unittest.main()
