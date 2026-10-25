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

"""Parity: the Rust port (antigravity_telemetry_rs) against the Python modules.

Each case runs the Python entry point and the Rust binary as subprocesses,
with the same input, environment and HOME, against one in-process mock OTLP
collector, then compares what each one sent (decompressed, with timestamps and
random trace/span IDs masked but key order kept), printed, exited with and
persisted.

Python's IDs are random (`secrets.token_hex`, `uuid4`), so IDs are checked
for shape and uniqueness, not equality; span durations are compared exactly.
"""

import gzip
import http.server
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from typing import Any, Dict, List, Optional, Tuple

_CURR_DIR = os.path.dirname(os.path.abspath(__file__))
if _CURR_DIR not in sys.path:
    sys.path.insert(0, _CURR_DIR)

import antigravity_telemetry  # noqa: E402
import session_exporter  # noqa: E402
import telemetry_hook  # noqa: E402
import telemetry_loader  # noqa: E402

RS_BIN = os.path.abspath(os.environ["ANTIGRAVITY_TELEMETRY_RS"])
HOST = "parity-host"
ENGINE_SOURCE = (
    b"import sys\nsys.stdin.read()\n# process_event\nprint('served-engine')\n"
)


class Collector:
    """A mock OTLP/HTTP collector that records every request."""

    def __init__(self, status: int = 200) -> None:
        self.status = status
        self.requests: List[Dict[str, Any]] = []
        collector = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length)
                encoding = self.headers.get("Content-Encoding")
                if encoding == "gzip":
                    body = gzip.decompress(body)
                collector.requests.append(
                    {
                        "path": self.path,
                        "gzip": encoding == "gzip",
                        "payload": json.loads(body.decode("utf-8")),
                    }
                )
                self._reply(collector.status, b'{"partialSuccess": {}}')

            def do_GET(self) -> None:
                if self.path == "/engine.py":
                    self._reply(200, ENGINE_SOURCE)
                else:
                    self._reply(404, b"404: Not Found")

            def _reply(self, status: int, body: bytes) -> None:
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: Any) -> None:
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_port}"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def take(self) -> List[Dict[str, Any]]:
        out, self.requests = self.requests, []
        return out

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()


def closed_port_url() -> str:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    return f"http://127.0.0.1:{port}"


TIME_KEYS = ("timeUnixNano", "startTimeUnixNano", "endTimeUnixNano")


def normalize(obj: Any, ids: List[str]) -> Any:
    """Mask timestamps and random IDs, keeping key order and span durations."""
    if isinstance(obj, dict):
        out: Dict[str, Any] = {}
        for k, v in obj.items():
            if k in TIME_KEYS:
                assert isinstance(v, str) and v.isdigit(), (k, v)
                out[k] = "<t>"
            elif k == "traceId":
                assert re.fullmatch(r"[0-9a-f]{32}", v), v
                ids.append(v)
                out[k] = "<trace>"
            elif k == "spanId":
                assert re.fullmatch(r"[0-9a-f]{16}", v), v
                ids.append(v)
                out[k] = "<span>"
            elif (
                k == "stringValue" and isinstance(v, str) and v.startswith("synthetic-")
            ):
                assert v[len("synthetic-") :].isdigit(), v
                out[k] = "synthetic-<t>"
            else:
                out[k] = normalize(v, ids)
        if "startTimeUnixNano" in obj and "endTimeUnixNano" in obj:
            out["<duration>"] = int(obj["endTimeUnixNano"]) - int(
                obj["startTimeUnixNano"]
            )
        return out
    if isinstance(obj, list):
        return [normalize(v, ids) for v in obj]
    return obj


def normalize_requests(reqs: List[Dict[str, Any]]) -> Tuple[str, List[str]]:
    ids: List[str] = []
    norm = [
        {"path": r["path"], "gzip": r["gzip"], "payload": normalize(r["payload"], ids)}
        for r in reqs
    ]
    # json.dumps without sort_keys: key order is part of the comparison.
    return json.dumps(norm, indent=1, ensure_ascii=False), ids


def id_pattern(ids: List[str]) -> List[int]:
    """Each ID replaced by the index of its first occurrence."""
    first: Dict[str, int] = {}
    return [first.setdefault(i, len(first)) for i in ids]


def base_env(home: str, **extra: str) -> Dict[str, str]:
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": home,
        "LANG": "C.UTF-8",
        "ANTIGRAVITY_HOST": HOST,
        "NO_PROXY": "*",
        "no_proxy": "*",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    env.update(extra)
    return env


class Run:
    def __init__(self, cp: subprocess.CompletedProcess) -> None:
        self.code = cp.returncode
        self.out = cp.stdout.decode("utf-8", "replace")
        self.err = cp.stderr.decode("utf-8", "replace")


def run(
    argv: List[str], env: Dict[str, str], stdin: bytes = b"", cwd: Optional[str] = None
) -> Run:
    cp = subprocess.run(
        argv, input=stdin, env=env, capture_output=True, timeout=30, cwd=cwd
    )
    return Run(cp)


def py(module: Any, *args: str) -> List[str]:
    return [sys.executable, module.__file__, *args]


def rs(*args: str) -> List[str]:
    return [RS_BIN, *args]


class ParityBase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.collector = Collector()

    def tearDown(self) -> None:
        self.collector.close()
        self.tmp.cleanup()

    def home(self, name: str) -> str:
        path = os.path.join(self.root, name)
        os.makedirs(path, exist_ok=True)
        return path

    def both(
        self,
        py_argv: List[str],
        rs_argv: List[str],
        env: Dict[str, str],
        stdin: bytes = b"",
    ) -> Tuple[Run, list, Run, list]:
        self.collector.take()
        p = run(py_argv, env, stdin)
        p_reqs = self.collector.take()
        r = run(rs_argv, env, stdin)
        r_reqs = self.collector.take()
        return p, p_reqs, r, r_reqs

    def assert_same_requests(self, p_reqs: list, r_reqs: list, label: str) -> None:
        p_norm, p_ids = normalize_requests(p_reqs)
        r_norm, r_ids = normalize_requests(r_reqs)
        self.assertEqual(p_norm, r_norm, label)
        # IDs are random in both, but which ones repeat must match: a payload
        # posted twice (`emit --count 2`) carries the same IDs both times.
        self.assertEqual(
            id_pattern(p_ids), id_pattern(r_ids), f"{label}: ID reuse differs"
        )


# ==============================================================================
# Hook events shared by the hook and `export` cases
# ==============================================================================

UNICODE_STATUS = "d" + chr(0xE9) + "j" + chr(0xE0) + " vu " + chr(0x1F600)

EVENTS: List[Dict[str, Any]] = [
    {
        "hook_event": "AfterModel",
        "llm_response": {
            "model": "gemini-3.8-pro",
            "usage_metadata": {
                "prompt_token_count": 120,
                "candidates_token_count": "45",
                "cached_content_token_count": 7.9,
            },
        },
    },
    {
        "hookEvent": "PostInvocation",
        "model": "model-from-data",
        "llmResponse": {
            "usageMetadata": {"promptTokenCount": 3},
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {"thought": True, "text": "thinking  hard\there"},
                            {"thought": True, "text": ""},
                            {"text": "answer"},
                        ]
                    }
                }
            ],
        },
    },
    {"hook_event": "AfterModel", "llm_response": {"model": 42}},
    {
        "hook_event": "BeforeTool",
        "tool_name": "invoke_subagent",
        "tool_input": {"Recipient": "", "role": None, "subagent_type": "researcher"},
    },
    {"hook_event": "PreToolUse", "toolName": "invoke_subagent", "toolInput": {}},
    {"hook_event": "BeforeTool", "tool_name": "run_command"},
    {"hook_event": "AfterTool", "tool_name": "run_command", "duration_ms": 1234.5},
    {
        "hook_event": "PostToolUse",
        "toolName": "Bash",
        "latency_ms": "70000",
        "is_error": True,
    },
    {"hook_event": "AfterTool", "tool_name": "view_file", "error": "boom"},
    {"hook_event": "AfterTool", "tool_name": 7, "duration_ms": 0},
    # CPython's dict.pop on an empty dict returns the default without hashing,
    # so an unhashable name does not raise in a fresh hook process.
    {"hook_event": "AfterTool", "tool_name": ["a", {"b": None}]},
    {"hook_event": "AfterAgent"},
    {"hook_event": "Stop", "status": "cancelled"},
    {"hook_event": "Stop", "status": 7},
    {"hook_event": "Stop", "status": 1.5},
    {"hook_event": "Stop", "status": True},
    {"hook_event": "Stop", "status": None},
    {"hook_event": "Stop", "status": UNICODE_STATUS},
    {"hook_event": "Unknown"},
    {"hook_event": ["AfterAgent"]},
    {},
]

# Inputs the Python hook raises on, with the warning it prints (None: a
# JSONDecodeError, whose message the Rust parser reproduces).
BAD_INPUTS: List[Tuple[str, Optional[str]]] = [
    ("[1, 2]", "'list' object has no attribute 'get'"),
    ('"text"', "'str' object has no attribute 'get'"),
    (
        '{"hook_event": "AfterModel", "llm_response": null}',
        "'NoneType' object has no attribute 'get'",
    ),
    (
        '{"hook_event": "AfterModel", "llm_response": {"usage_metadata": {"prompt_token_count": "x"}}}',
        "invalid literal for int() with base 10: 'x'",
    ),
    (
        '{"hook_event": "AfterModel", "llm_response": {"usage_metadata": {"prompt_token_count": null}}}',
        "int() argument must be a string, a bytes-like object or a real number, not 'NoneType'",
    ),
    (
        '{"hook_event": "AfterModel", "llm_response": {"candidates": [{"content": {"parts": [{"thought": 1, "text": 5}]}}]}}',
        "'int' object has no attribute 'split'",
    ),
    (
        '{"hook_event": "AfterModel", "llm_response": {"candidates": 5}}',
        "'int' object is not iterable",
    ),
    ('{"hook_event": "BeforeTool", "tool_name": {"a": 1}}', "unhashable type: 'dict'"),
    (
        '{"hook_event": "AfterTool", "duration_ms": "fast"}',
        "could not convert string to float: 'fast'",
    ),
    (
        '{"hook_event": "BeforeTool", "tool_name": "invoke_subagent", "tool_input": []}',
        "'list' object has no attribute 'get'",
    ),
    ("not json", None),
    ('{"unterminated": ', None),
    ('{"a": 1} trailing', None),
    ('{"a": "tab\there"}', None),
    ('{"a" 1}', None),
    ("[1, 2,]", None),
]

EMPTY_INPUTS = ["", "   \n"]


class HookParityTest(ParityBase):
    """`telemetry_hook.py` vs `antigravity_telemetry_rs telemetry-hook`."""

    def env(self) -> Dict[str, str]:
        return base_env(
            self.home("h"), ANTIGRAVITY_OTLP_ENDPOINT=self.collector.url + "/"
        )

    def test_events(self) -> None:
        for event in EVENTS:
            stdin = json.dumps(event).encode()
            p, p_reqs, r, r_reqs = self.both(
                py(telemetry_hook), rs("telemetry-hook"), self.env(), stdin
            )
            label = json.dumps(event)
            self.assertEqual((p.code, p.out, p.err), (r.code, r.out, r.err), label)
            self.assertEqual(r.out, '{"decision": "allow"}\n', label)
            self.assert_same_requests(p_reqs, r_reqs, label)

    def test_events_on_unicode_and_ascii_escaped_input(self) -> None:
        stdin = json.dumps(
            {"hook_event": "Stop", "status": UNICODE_STATUS}, ensure_ascii=False
        ).encode()
        p, p_reqs, r, r_reqs = self.both(
            py(telemetry_hook), rs("telemetry-hook"), self.env(), stdin
        )
        self.assertEqual((p.out, p.err), (r.out, r.err))
        self.assert_same_requests(p_reqs, r_reqs, "unicode")
        self.assertIn(
            UNICODE_STATUS, json.dumps(r_reqs[0]["payload"], ensure_ascii=False)
        )

    def test_bad_and_empty_inputs(self) -> None:
        for raw, warning in BAD_INPUTS:
            p, p_reqs, r, r_reqs = self.both(
                py(telemetry_hook), rs("telemetry-hook"), self.env(), raw.encode()
            )
            self.assertEqual((p.code, p.out), (r.code, r.out), raw)
            self.assertEqual((p_reqs, r_reqs), ([], []), raw)
            self.assertTrue(
                r.err.startswith("[telemetry_hook] Warning: "), (raw, r.err)
            )
            self.assertEqual(r.err, p.err, raw)
            if warning is not None:
                self.assertEqual(p.err, f"[telemetry_hook] Warning: {warning}\n", raw)
        for raw in EMPTY_INPUTS:
            p, p_reqs, r, r_reqs = self.both(
                py(telemetry_hook), rs("telemetry-hook"), self.env(), raw.encode()
            )
            self.assertEqual(
                (p.code, p.out, p.err, p_reqs),
                (r.code, r.out, r.err, r_reqs),
                repr(raw),
            )

    def test_collector_down_still_allows(self) -> None:
        env = base_env(self.home("h"), ANTIGRAVITY_OTLP_ENDPOINT=closed_port_url())
        stdin = json.dumps(EVENTS[0]).encode()
        p = run(py(telemetry_hook), env, stdin)
        r = run(rs("telemetry-hook"), env, stdin)
        self.assertEqual((p.code, p.out, p.err), (r.code, r.out, r.err))
        self.assertEqual(r.out, '{"decision": "allow"}\n')

    def test_argv0_dispatch(self) -> None:
        link = os.path.join(self.root, "telemetry_hook.py")
        os.symlink(RS_BIN, link)
        stdin = json.dumps(EVENTS[-3]).encode()
        p, p_reqs, r, r_reqs = self.both(py(telemetry_hook), [link], self.env(), stdin)
        self.assertEqual((p.out, p.err), (r.out, r.err))
        self.assert_same_requests(p_reqs, r_reqs, "argv0")


class ExportParityTest(ParityBase):
    """`antigravity_telemetry.py export` vs `antigravity_telemetry_rs export`."""

    def test_events_hook_mode_verbose(self) -> None:
        env = base_env(self.home("h"))
        args = ["export", "--endpoint", self.collector.url, "--hook-mode", "--verbose"]
        for event in EVENTS:
            stdin = json.dumps(event).encode()
            p, p_reqs, r, r_reqs = self.both(
                py(antigravity_telemetry, *args), rs(*args), env, stdin
            )
            label = json.dumps(event)
            self.assertEqual((p.code, p.out, p.err), (r.code, r.out, r.err), label)
            self.assertEqual(r.out, "{}\n")
            self.assert_same_requests(p_reqs, r_reqs, label)

    def test_bad_inputs_and_files(self) -> None:
        env = base_env(self.home("h"))
        args = ["export", "--endpoint", self.collector.url, "--verbose"]
        for raw, warning in BAD_INPUTS:
            p, p_reqs, r, r_reqs = self.both(
                py(antigravity_telemetry, *args), rs(*args), env, raw.encode()
            )
            self.assertEqual((p.code, p.out, p_reqs), (r.code, r.out, r_reqs), raw)
            self.assertEqual(r.err, p.err, raw)
            self.assertTrue(r.err.startswith("[export] Warning: "), raw)
            if warning is not None:
                self.assertEqual(r.err, f"[export] Warning: {warning}\n", raw)

        event_file = os.path.join(self.root, "event.json")
        with open(event_file, "w", encoding="utf-8") as f:
            json.dump(EVENTS[6], f)
        file_args = args + ["--file", event_file]
        p, p_reqs, r, r_reqs = self.both(
            py(antigravity_telemetry, *file_args), rs(*file_args), env
        )
        self.assertEqual((p.code, p.out, p.err), (r.code, r.out, r.err))
        self.assert_same_requests(p_reqs, r_reqs, "--file")

        missing = args + [
            "--file",
            os.path.join(self.root, "missing.json"),
            "--hook-mode",
        ]
        p, _, r, _ = self.both(py(antigravity_telemetry, *missing), rs(*missing), env)
        self.assertEqual((p.code, p.out, p.err), (r.code, r.out, r.err))
        self.assertIn("No such file or directory", r.err)

    def test_non_2xx_is_reported_not_raised(self) -> None:
        self.collector.status = 500
        env = base_env(self.home("h"))
        args = ["export", "--endpoint", self.collector.url, "--verbose"]
        stdin = json.dumps(EVENTS[0]).encode()
        p, p_reqs, r, r_reqs = self.both(
            py(antigravity_telemetry, *args), rs(*args), env, stdin
        )
        self.assertEqual((p.code, p.out, p.err), (r.code, r.out, r.err))
        self.assertIn("-> 500 (HTTP 500: Internal Server Error)", r.err)
        self.assert_same_requests(p_reqs, r_reqs, "500")


class EmitParityTest(ParityBase):
    """`antigravity_telemetry.py emit` vs `antigravity_telemetry_rs emit`."""

    VARIANTS = [
        ["--json"],
        ["--json", "--metrics-only"],
        ["--json", "--traces-only", "--tool-latency-ms", "70000.5"],
        [
            "--json",
            "--count",
            "2",
            "--model",
            "gemini-x",
            "--tool",
            "Bash",
            "--tokens-in",
            "0",
        ],
        ["--json", "--tool-latency-ms=0.001", "--tokens-cached", "-5"],
        ["--json", "--count", "0"],
        [],
    ]

    def args(self, extra: List[str], endpoint: Optional[str] = None) -> List[str]:
        return [
            "emit",
            "--endpoint",
            (endpoint or self.collector.url) + "/",
            "--host",
            HOST,
            *extra,
        ]

    def test_variants(self) -> None:
        env = base_env(self.home("h"))
        for extra in self.VARIANTS:
            a = self.args(extra)
            p, p_reqs, r, r_reqs = self.both(py(antigravity_telemetry, *a), rs(*a), env)
            self.assertEqual((p.code, p.out, p.err), (r.code, r.out, r.err), extra)
            self.assert_same_requests(p_reqs, r_reqs, " ".join(extra))

    def test_verbose_payload_text(self) -> None:
        env = base_env(self.home("h"))
        a = self.args(["--verbose"])
        p, _, r, _ = self.both(py(antigravity_telemetry, *a), rs(*a), env)

        def mask(text: str) -> str:
            text = re.sub(
                r'"(time|startTime|endTime)UnixNano": "\d+"',
                r'"\1UnixNano": "<t>"',
                text,
            )
            text = re.sub(r'"traceId": "[0-9a-f]{32}"', '"traceId": "<id>"', text)
            text = re.sub(r'"spanId": "[0-9a-f]{16}"', '"spanId": "<id>"', text)
            return re.sub(r"synthetic-\d+", "synthetic-<t>", text)

        # Byte-for-byte, after masking: indent=2 layout, float repr, key order.
        self.assertEqual(mask(p.out), mask(r.out))
        self.assertIn("OTLP Traces Payload:", r.out)

    def test_failures(self) -> None:
        env = base_env(self.home("h"))
        self.collector.status = 500
        for extra in (["--json"], []):
            a = self.args(extra)
            p, p_reqs, r, r_reqs = self.both(py(antigravity_telemetry, *a), rs(*a), env)
            self.assertEqual((p.code, p.out, p.err), (r.code, r.out, r.err), extra)
            self.assertEqual(r.code, 2)
            self.assertIn(
                "[TelemetryHttpClient] HTTP 500: Internal Server Error", r.err
            )
            self.assert_same_requests(p_reqs, r_reqs, "500")
        down = closed_port_url()
        a = ["emit", "--endpoint", down, "--host", HOST]
        p = run(py(antigravity_telemetry, *a), env)
        r = run(rs(*a), env)
        self.assertEqual((p.code, p.out, p.err), (r.code, r.out, r.err))
        self.assertIn("URLError: [Errno", r.err)

    def test_argument_errors_exit_2(self) -> None:
        env = base_env(self.home("h"))
        for bad in (
            ["emit", "--count", "x"],
            ["emit", "--tokens", "1"],
            ["emit", "--nope"],
            ["bogus"],
            [],
        ):
            p = run(py(antigravity_telemetry, *bad), env)
            r = run(rs(*bad), env)
            self.assertEqual((p.code, p.out), (r.code, r.out), bad)
            self.assertEqual(r.code, 2, bad)


# ==============================================================================
# status / setup
# ==============================================================================

LEGACY_SETTINGS = {
    "theme": "dark",
    "hooks": {
        "AfterModel": [
            {
                "matcher": "*",
                "hooks": [
                    {
                        "name": "telemetry-hook",
                        "command": "python3 ~/.gemini/hooks/telemetry_hook.py",
                    },
                    {"name": "mine", "command": "echo hi"},
                ],
            }
        ],
        "BeforeTool": [{"hooks": [{"command": "/x/stream-hook.sh"}]}],
        "Stop": [{"hooks": [{"command": "say done"}]}],
    },
}


def write_transcript(brain: str, convo: str, lines: List[bytes]) -> str:
    logs = os.path.join(brain, convo, ".system_generated", "logs")
    os.makedirs(logs, exist_ok=True)
    path = os.path.join(logs, "transcript.jsonl")
    with open(path, "wb") as f:
        f.write(b"".join(lines))
    return path


class StatusSetupParityTest(ParityBase):
    def make_home(self) -> Tuple[str, str]:
        home = self.home("h")
        gem = os.path.join(home, ".gemini")
        write_transcript(os.path.join(gem, "antigravity", "brain"), "a1", [b"{}\n"])
        write_transcript(os.path.join(gem, "antigravity", "brain"), "a2", [b"{}\n"])
        write_transcript(
            os.path.join(gem, "antigravity", "brain"), ".hidden", [b"{}\n"]
        )
        write_transcript(os.path.join(gem, "antigravity-cli", "brain"), "c1", [b"{}\n"])
        settings = os.path.join(home, "settings.json")
        with open(settings, "w", encoding="utf-8") as f:
            json.dump(LEGACY_SETTINGS, f)
        return home, settings

    @unittest.skipUnless(
        os.path.exists("/usr/bin/pgrep"), "Python status shells out to /usr/bin/pgrep"
    )
    def test_status(self) -> None:
        home, settings = self.make_home()
        env = base_env(home)
        comparable = ("agy_cli", "transcripts", "legacy_gemini_hooks")
        for endpoint, status in (
            (self.collector.url, 200),
            (self.collector.url, 503),
            (closed_port_url(), None),
        ):
            if status:
                self.collector.status = status
            a = [
                "status",
                "--json",
                "--endpoint",
                endpoint + "/",
                "--settings-path",
                settings,
                "--timeout",
                "2",
            ]
            p, p_reqs, r, r_reqs = self.both(py(antigravity_telemetry, *a), rs(*a), env)
            pj, rj = json.loads(p.out), json.loads(r.out)
            self.assertEqual(list(pj), list(rj))
            self.assertEqual(list(pj["checks"]), list(rj["checks"]))
            for key in ("host", "endpoint"):
                self.assertEqual(pj[key], rj[key])
            for name in comparable:
                self.assertEqual(pj["checks"][name], rj["checks"][name], name)
            for name in ("collector_metrics", "collector_traces"):
                pc, rc = pj["checks"][name], rj["checks"][name]
                self.assertEqual(
                    (pc["passed"], pc["http_status"]),
                    (rc["passed"], rc["http_status"]),
                    name,
                )
                if not pc["passed"]:
                    self.assertEqual(pc["message"], rc["message"], name)
                else:
                    self.assertRegex(rc["message"], r"^HTTP 200 \(\d+\.\dms\)$")
            self.assertEqual(
                rj["checks"]["transcripts"]["counts"],
                {"antigravity": 2, "agy": 1, "antigravity-ide": 0},
            )
            self.assertEqual(
                rj["checks"]["legacy_gemini_hooks"]["events"],
                ["AfterModel", "BeforeTool"],
            )
            self.assertRegex(
                rj["timestamp"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d{6})?\+00:00$"
            )
            self.assert_same_requests(p_reqs, r_reqs, f"status {status}")

        # The text report, minus the exporter checks (installed differently by
        # design) and latencies.
        self.collector.status = 200
        a = ["status", "--endpoint", self.collector.url, "--settings-path", settings]
        p, _, r, _ = self.both(py(antigravity_telemetry, *a), rs(*a), env)

        def keep(text: str) -> List[str]:
            lines = [ln for ln in text.splitlines() if "exporter_" not in ln]
            return [re.sub(r"\(\d+\.\dms\)", "(<ms>)", ln) for ln in lines]

        self.assertEqual(keep(p.out), keep(r.out))

    def test_setup_dry_run(self) -> None:
        home, settings = self.make_home()
        env = base_env(home)
        with open(settings, "rb") as f:
            before = f.read()
        for fmt in (["--json"], []):
            a = [
                "setup",
                "--dry-run",
                "--endpoint",
                self.collector.url + "/",
                "--settings-path",
                settings,
                *fmt,
            ]
            p, _, r, _ = self.both(py(antigravity_telemetry, *a), rs(*a), env)
            self.assertEqual((p.code, r.code), (0, 0))
            if fmt:
                pj, rj = json.loads(p.out), json.loads(r.out)
                self.assertEqual(list(pj), list(rj))
                for key in (
                    "status",
                    "launch_agent",
                    "endpoint",
                    "agy",
                    "dry_run",
                    "legacy_hooks_removed",
                ):
                    self.assertEqual(pj[key], rj[key], key)
                self.assertTrue(
                    rj["exporter"].endswith("/.gemini/hooks/antigravity-telemetry-rs")
                )
            else:
                self.assertEqual(
                    [ln for ln in p.out.splitlines() if not ln.startswith("Exporter:")],
                    [ln for ln in r.out.splitlines() if not ln.startswith("Exporter:")],
                )
        with open(settings, "rb") as f:
            self.assertEqual(f.read(), before)
        self.assertFalse(os.path.exists(os.path.join(home, ".gemini", "hooks")))

        with open(settings, "w", encoding="utf-8") as f:
            f.write("{not json")
        a = ["setup", "--dry-run", "--json", "--settings-path", settings]
        p, _, r, _ = self.both(py(antigravity_telemetry, *a), rs(*a), env)
        pj, rj = json.loads(p.out), json.loads(r.out)
        self.assertEqual(list(pj), list(rj))
        self.assertTrue(rj["legacy_cleanup"].startswith("skipped, unreadable: "))


# ==============================================================================
# session exporter
# ==============================================================================

CHILD_ID = "0123abcd-0123-4567-89ab-0123456789ab"
TWO_DAYS = 2 * 86400


def jl(obj: Any) -> bytes:
    return (json.dumps(obj) + "\n").encode()


def build_exporter_fixture(home: str) -> Dict[str, str]:
    gem = os.path.join(home, ".gemini")
    ag = os.path.join(gem, "antigravity", "brain")
    cli = os.path.join(gem, "antigravity-cli", "brain")
    ide = os.path.join(gem, "antigravity-ide", "brain")
    change = (
        "<USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from "
        "Gemini 3.7 Flash to Gemini 3.8 Pro (High). Carry on"
    )
    paths = {}
    paths["parent"] = write_transcript(
        ag,
        "parent",
        [
            jl({"type": "USER_INPUT", "content": change}),
            jl(
                {
                    "type": "PLANNER_RESPONSE",
                    "thinking": "x" * 41,
                    "tool_calls": [
                        {"name": "run_command"},
                        {"name": "write_to_file"},
                        {"name": "invoke_subagent"},
                        {"name": "view_file"},
                        {},
                    ],
                }
            ),
            jl(
                {
                    "type": "GENERIC",
                    "content": f'{{\\"conversationId\\": \\"{CHILD_ID}\\"}}',
                }
            ),
            b"\n",
            b"   \n",
            b"not json\n",
            b"[1, 2]\n",
            jl(
                {
                    "type": "PLANNER_RESPONSE",
                    "tool_calls": [{"name": "run_command"}, {"name": ["bad"]}],
                }
            ),
            jl({"type": "PLANNER_RESPONSE", "tool_calls": "ab"}),
            jl({"type": "PLANNER_RESPONSE", "tool_calls": {}}),
            jl({"type": "GENERIC", "thinking": 5, "content": 3}),
            b'{"type": "GENERIC", "content": "caf\xff\xfee"}\r\n',
            b'{"type": "PLANNER_RESPONSE"}\r',
            jl(
                {
                    "type": "PLANNER_RESPONSE",
                    "tool_calls": [{"name": f"tool_{i}"} for i in range(22)],
                }
            ),
            b'{"type": "PLANNER_RESPONSE", "tool_calls": [{"name": "partial"',
        ],
    )
    paths["child"] = write_transcript(
        ag,
        CHILD_ID,
        [
            jl(
                {
                    "type": "PLANNER_RESPONSE",
                    "tool_calls": [{"name": "replace_file_content"}],
                }
            )
        ],
    )
    write_transcript(ag, ".hidden", [jl({"type": "PLANNER_RESPONSE"})])
    paths["cli"] = write_transcript(
        cli,
        "cli-convo",
        [
            jl({"type": "PLANNER_RESPONSE", "tool_calls": [{"name": "run_command"}]}),
            jl(
                {
                    "type": "USER_INPUT",
                    "content": "<USER_SETTINGS_CHANGE> nothing parseable",
                }
            ),
        ],
    )
    paths["ide_legacy_model"] = write_transcript(
        ide,
        "ide-legacy",
        [
            jl({"type": "USER_INPUT", "content": "hi"}),
            jl(
                {
                    "type": "USER_INPUT",
                    "content": change.replace(
                        "3.8 Pro (High)", "Claude Opus 5 (Thinking)"
                    ),
                }
            ),
            jl(
                {
                    "type": "PLANNER_RESPONSE",
                    "tool_calls": [{"name": "invoke_subagent"}],
                }
            ),
        ],
    )
    paths["ide_int_state"] = write_transcript(
        ide,
        "ide-int",
        [jl({"type": "PLANNER_RESPONSE", "tool_calls": [{"name": "x"}]})],
    )
    paths["old"] = write_transcript(ide, "old", [jl({"type": "PLANNER_RESPONSE"})])

    proj = os.path.join(home, ".claude", "projects", "proj")
    os.makedirs(proj, exist_ok=True)
    claude_lines = [
        jl(
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "model": "claude-opus-5",
                    "usage": {
                        "input_tokens": 100,
                        "output_tokens": 50,
                        "cache_read_input_tokens": 200,
                        "cache_creation_input_tokens": 300,
                        "thinking_tokens": 9,
                    },
                    "content": [
                        {"type": "thinking", "thinking": "y" * 30},
                        {"type": "tool_use", "name": "Bash"},
                        {"type": "tool_use", "name": "Edit"},
                        {"type": "tool_use", "name": "Agent"},
                        {"type": "tool_use", "name": "Read"},
                        {"type": "tool_use"},
                        "not a block",
                    ],
                },
            }
        ),
        jl({"type": "user", "message": {"role": "user", "content": "hello"}}),
        jl(
            {
                "message": {
                    "role": "assistant",
                    "model": "claude-sonnet-5",
                    "content": "plain text",
                    "usage": {},
                }
            }
        ),
        jl({"type": "assistant", "message": None}),
        jl({"type": "assistant", "message": {"usage": [1], "content": []}}),
        jl(
            {
                "type": "assistant",
                "message": {
                    "usage": {"input_tokens": 1.5},
                    "content": [{"type": "thinking", "thinking": ["a", "b"]}],
                },
            }
        ),
        jl([1]),
    ]
    paths["claude"] = os.path.join(proj, "session-1.jsonl")
    with open(paths["claude"], "wb") as f:
        f.write(b"".join(claude_lines))
    with open(os.path.join(proj, ".hidden.jsonl"), "wb") as f:
        f.write(claude_lines[0])
    with open(os.path.join(proj, "notes.txt"), "wb") as f:
        f.write(claude_lines[0])
    with open(os.path.join(home, ".claude", "projects", "top.jsonl"), "wb") as f:
        f.write(claude_lines[0])

    now = time.time()
    old = int((now - TWO_DAYS) * 1e9)
    os.utime(paths["old"], ns=(old, old))
    os.utime(paths["ide_legacy_model"], ns=(old, old))
    return paths


def write_exporter_state(home: str, paths: Dict[str, str]) -> None:
    """Pre-existing state: a legacy-model entry and a legacy int entry."""
    tokens = {"input": 0, "output": 0, "cached": 0, "thinking": 0}
    state = {
        paths["ide_legacy_model"]: {
            "service": "antigravity",
            "model": "gemini-3.7-flash",
            "offset": 0,
            "turns": 0,
            "tools": {},
            "subagents": 0,
            "tokens": tokens,
            "mtime": 0,
        },
        paths["ide_int_state"]: 5,
        os.path.join(home, "gone.jsonl"): {
            "offset": 1,
            "turns": 3,
            "tokens": {"input": 2},
            "model": None,
        },
        "junk": "dropped",
    }
    path = os.path.join(home, ".gemini", "antigravity", ".telemetry_state.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(state, f)


class SessionExporterParityTest(ParityBase):
    """`session_exporter.py` vs `antigravity_telemetry_rs session-exporter`."""

    def setUp(self) -> None:
        super().setUp()
        fixture = self.home("fixture")
        self.paths = build_exporter_fixture(fixture)
        self.homes = {}
        for impl in ("py", "rs"):
            home = os.path.join(self.root, impl)
            shutil.copytree(fixture, home, symlinks=True)
            self.homes[impl] = home
            write_exporter_state(
                home, {k: v.replace(fixture, home) for k, v in self.paths.items()}
            )

    def state(self, impl: str) -> Any:
        home = self.homes[impl]
        with open(
            os.path.join(home, ".gemini", "antigravity", ".telemetry_state.json"),
            encoding="utf-8",
        ) as f:
            text = f.read()
        return json.loads(text.replace(home, "<HOME>")), text.replace(home, "<HOME>")

    def scan(self, *args: str) -> List[Dict[str, Any]]:
        self.collector.take()
        common = ["--endpoint", self.collector.url + "/", "--host", HOST, *args]
        p = run(py(session_exporter, *common), base_env(self.homes["py"]))
        p_reqs = self.collector.take()
        r = run(rs("session-exporter", *common), base_env(self.homes["rs"]))
        r_reqs = self.collector.take()
        label = " ".join(args)
        self.assertEqual((p.code, p.out, p.err), (r.code, r.out, r.err), label)
        self.assert_same_requests(p_reqs, r_reqs, label)
        (p_state, p_text), (r_state, r_text) = self.state("py"), self.state("rs")
        self.assertEqual(p_state, r_state, label)
        # Byte-identical state file: indent=2, ensure_ascii, key order, floats.
        self.assertEqual(p_text, r_text, label)
        return p_reqs

    def append(self, key: str, data: bytes) -> None:
        t = time.time_ns()
        for impl in ("py", "rs"):
            path = self.paths[key].replace(
                os.path.join(self.root, "fixture"), self.homes[impl]
            )
            with open(path, "ab") as f:
                f.write(data)
            os.utime(path, ns=(t, t))

    def test_once_incremental_then_backfill(self) -> None:
        reqs = self.scan("--once")
        paths = [r["path"] for r in reqs]
        self.assertEqual(paths, ["/v1/traces", "/v1/traces"] + ["/v1/metrics"] * 4)
        self.assertEqual(
            len(reqs[0]["payload"]["resourceSpans"][0]["scopeSpans"][0]["spans"]), 20
        )

        # Nothing new: no traces, only the cumulative state.
        reqs = self.scan("--once")
        self.assertEqual([r["path"] for r in reqs], ["/v1/metrics"] * 4)

        self.append(
            "parent",
            b' "x"}]}\n'
            + jl({"type": "PLANNER_RESPONSE", "tool_calls": [{"name": "Edit"}]}),
        )
        self.append(
            "claude",
            jl(
                {
                    "type": "assistant",
                    "message": {
                        "model": "claude-x",
                        "content": [{"type": "tool_use", "name": "Write"}],
                    },
                }
            ),
        )
        self.scan("--once")

        self.scan("--backfill")

    def test_collector_errors_are_logged(self) -> None:
        self.collector.status = 500
        self.scan("--once")
        down = closed_port_url()
        common = ["--once", "--endpoint", down, "--host", HOST]
        p = run(py(session_exporter, *common), base_env(self.homes["py"]))
        r = run(rs("session-exporter", *common), base_env(self.homes["rs"]))
        self.assertEqual((p.code, p.out, p.err), (r.code, r.out, r.err))
        self.assertIn("[session_exporter] Export to ", r.err)


# ==============================================================================
# loader
# ==============================================================================


class LoaderParityTest(ParityBase):
    """`telemetry_loader.py` vs `antigravity_telemetry_rs telemetry-loader`."""

    def env(self, home: str, source_url: Optional[str] = None) -> Dict[str, str]:
        return base_env(
            home,
            ANTIGRAVITY_OTLP_ENDPOINT=self.collector.url,
            ANTIGRAVITY_HOOK_SOURCE_URL=source_url or closed_port_url() + "/engine.py",
            ANTIGRAVITY_TELEMETRY_PYTHON=sys.executable,
        )

    def cache(self, home: str) -> str:
        return os.path.join(home, ".gemini", "hooks", ".engine.py")

    def seed(self, home: str, content: bytes) -> None:
        os.makedirs(os.path.dirname(self.cache(home)), exist_ok=True)
        with open(self.cache(home), "wb") as f:
            f.write(content)

    def test_cached_engine_runs(self) -> None:
        home = self.home("h")
        with open(telemetry_hook.__file__, "rb") as f:
            self.seed(home, f.read())
        stdin = json.dumps(EVENTS[0]).encode()
        p, p_reqs, r, r_reqs = self.both(
            py(telemetry_loader), rs("telemetry-loader"), self.env(home), stdin
        )
        self.assertEqual((p.code, p.out, p.err), (r.code, r.out, r.err))
        self.assertEqual(r.out, '{"decision": "allow"}\n')
        self.assert_same_requests(p_reqs, r_reqs, "cached engine")
        self.assertEqual(len(r_reqs), 1)

    def test_engine_exit_code_and_silence(self) -> None:
        home = self.home("h")
        self.seed(home, b"import sys\nprint('custom')\nsys.exit(3)\n")
        p, _, r, _ = self.both(
            py(telemetry_loader), rs("telemetry-loader"), self.env(home)
        )
        self.assertEqual((p.code, p.out), (r.code, r.out))
        self.assertEqual((r.code, r.out), (3, "custom\n"))

        self.seed(home, b"pass\n")
        p, _, r, _ = self.both(
            py(telemetry_loader), rs("telemetry-loader"), self.env(home)
        )
        self.assertEqual((p.code, p.out), (r.code, r.out))
        self.assertEqual((r.code, r.out), (0, '{"decision": "allow"}\n'))

    def test_no_cache_and_no_source_fails_open(self) -> None:
        home = self.home("h")
        p, _, r, _ = self.both(
            py(telemetry_loader), rs("telemetry-loader"), self.env(home)
        )
        self.assertEqual((p.code, p.out), (r.code, r.out))
        self.assertEqual(r.out, '{"decision": "allow"}\n')
        self.assertFalse(os.path.exists(self.cache(home)))

    @unittest.skipUnless(shutil.which("curl"), "the Rust loader downloads with curl")
    def test_first_use_downloads_engine(self) -> None:
        results = []
        for impl, argv in (
            ("py", py(telemetry_loader)),
            ("rs", rs("telemetry-loader")),
        ):
            home = self.home(impl)
            out = run(argv, self.env(home, self.collector.url + "/engine.py"))
            with open(self.cache(home), "rb") as f:
                cached = f.read()
            mode = os.stat(self.cache(home)).st_mode & 0o777
            results.append((out.code, out.out, cached, mode))
        self.assertEqual(results[0], results[1])
        self.assertEqual(results[1], (0, "served-engine\n", ENGINE_SOURCE, 0o755))


if __name__ == "__main__":
    unittest.main()
