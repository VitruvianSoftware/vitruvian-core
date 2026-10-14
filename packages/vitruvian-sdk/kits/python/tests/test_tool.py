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
"""The kit against a link made of two files: what the app will have sent,
written before the tool starts, and what the tool writes. A file never blocks,
and its end is the end of the link, so no test here waits long.

Ported test for test from Tests/VitruvianToolKitTests/ToolTests.swift. The
standard library's unittest, so that `python3 -m unittest` runs them with
nothing installed, on the Python 3.9 every Mac has as well as on Bazel's.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from vitruvian_tool_kit import (  # noqa: E402
    METHODS,
    AppUnreachable,
    CommandRefused,
    Feature,
    PanelAnswer,
    PanelEvent,
    Refusal,
    RefusalCode,
    RPCErrorObject,
    Tool,
    UIChoiceOption,
    UIListRow,
    button,
    choice,
    divider,
    field,
    heading,
    image,
    link,
    list_,
    progress,
    row,
    spacer,
    text,
    toggle,
    tree,
)


class Bench:
    def __init__(self):
        self.folder = tempfile.mkdtemp(prefix="vitruvian-tool-kit-")
        self.sent = ""
        self.ends = []

    def app(self, line):
        self.sent += line + "\n"
        return self

    def hello(self, versions='["1"]', features=None):
        """`features` is what the app says it has, as JSON; None is an app
        from before the field, which says nothing."""
        said = "" if features is None else ',"features":%s' % features
        return self.app(
            '{"jsonrpc":"2.0","id":"hello","method":"initialize","params":{"protocolVersions":%s,'
            '"language":"de-DE","dataFolder":"/tmp/kit-data"%s}}' % (versions, said)
        )

    def run(self, command, id):
        return self.app(
            '{"jsonrpc":"2.0","id":%d,"method":"command/run","params":{"command":"%s"}}'
            % (id, command)
        )

    def goodbye(self):
        return self.app('{"jsonrpc":"2.0","method":"shutdown"}')

    def tool(self, build=lambda tool: None):
        with open(
            os.path.join(self.folder, "from-app"), "w", encoding="utf-8"
        ) as handle:
            handle.write(self.sent)
        self.ends = [
            os.open(os.path.join(self.folder, "from-app"), os.O_RDONLY),
            os.open(
                os.path.join(self.folder, "to-app"),
                os.O_WRONLY | os.O_CREAT | os.O_TRUNC,
            ),
        ]
        tool = Tool(version="9.9.9", input=self.ends[0], output=self.ends[1])
        build(tool)
        return tool

    def written(self):
        with open(os.path.join(self.folder, "to-app"), encoding="utf-8") as handle:
            return [json.loads(line) for line in handle.read().split("\n") if line]

    def done(self):
        for end in self.ends:
            os.close(end)
        shutil.rmtree(self.folder, ignore_errors=True)


def result(id, value):
    return {"jsonrpc": "2.0", "id": id, "result": value}


def failure(id, code, message):
    return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}


class ToolTests(unittest.TestCase):
    def setUp(self):
        self.bench = Bench()

    def tearDown(self):
        self.bench.done()

    def test_every_request_a_tool_may_send_is_a_call_on_the_app(self):
        calls = []

        def look(app):
            for group in [name for name in vars(app) if not name.startswith("_")]:
                calls.extend(
                    group + "/" + name
                    for name in dir(getattr(app, group))
                    if not name.startswith("_")
                )
            calls.extend(
                name for name in ("log",) if callable(getattr(app, name, None))
            )

        tool = self.bench.hello().goodbye().tool()
        tool.on_start = look
        self.assertEqual(tool.serve(), 0)
        wanted = [m.method for m in METHODS if m.sender == "tool"]
        python = [
            re.sub("([A-Z])", lambda c: "_" + c.group(1).lower(), method)
            for method in wanted
        ]
        self.assertEqual(sorted(calls), sorted(python))
        self.assertEqual(len(wanted), 15, "each message once")

    def test_hello_a_command_and_goodbye(self):
        seen = []

        def hello(app):
            seen.extend([app.language, app.data_folder])

        tool = (
            self.bench.hello()
            .run("hello", 2)
            .goodbye()
            .tool(lambda t: t.command("hello", hello))
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(seen, ["de-DE", "/tmp/kit-data"])
        self.assertEqual(
            self.bench.written(),
            [
                result("hello", {"protocolVersion": "1", "toolVersion": "9.9.9"}),
                result(2, {}),
            ],
        )

    def test_a_handler_calls_the_app_and_reads_the_answer(self):
        read = []

        def copy(app):
            read.append(app.clipboard.read_text().text)
            app.notify.hud(icon="doc.on.clipboard", message="Read it")

        tool = (
            self.bench.hello()
            .run("copy", 2)
            .app('{"jsonrpc":"2.0","id":1,"result":{"text":"from the clipboard"}}')
            .app('{"jsonrpc":"2.0","id":2,"result":{}}')
            .goodbye()
            .tool(lambda t: t.command("copy", copy))
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(read, ["from the clipboard"])
        written = self.bench.written()
        self.assertEqual(len(written), 4)
        self.assertEqual(
            written[1], {"jsonrpc": "2.0", "id": 1, "method": "clipboard/readText"}
        )
        self.assertEqual(
            written[2],
            {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "notify/hud",
                "params": {"icon": "doc.on.clipboard", "message": "Read it"},
            },
        )
        self.assertEqual(written[3], result(2, {}), "the command is answered last")

    def test_an_answer_to_another_request_is_not_taken_for_this_one(self):
        read = []
        tool = (
            self.bench.hello()
            .run("copy", 2)
            .app(
                '{"jsonrpc":"2.0","id":98,"error":{"code":-32004,"message":"not available right now"}}'
            )
            .app('{"jsonrpc":"2.0","id":99,"result":{"text":"somebody else\'s"}}')
            .app('{"jsonrpc":"2.0","id":1,"result":{"text":"mine"}}')
            .goodbye()
            .tool(
                lambda t: t.command(
                    "copy", lambda app: read.append(app.clipboard.read_text().text)
                )
            )
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(read, ["mine"])
        self.assertEqual(self.bench.written()[-1], result(2, {}))

    def test_a_refusal_the_handler_lets_through_refuses_the_command(self):
        tool = (
            self.bench.hello()
            .run("hello", 7)
            .app(
                '{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"not listed in uses","data":{"service":"notify"}}}'
            )
            .goodbye()
            .tool(
                lambda t: t.command(
                    "hello",
                    lambda app: app.notify.hud(icon="hand.wave", message="Hello"),
                )
            )
        )
        self.assertEqual(tool.serve(), 0)
        last = self.bench.written()[-1]
        self.assertEqual(last["id"], 7)
        self.assertEqual(last["error"]["code"], -32010)
        self.assertEqual(
            last["error"]["data"]["code"],
            -32001,
            "the app's reason goes with it, for the log",
        )

    def test_a_handler_may_catch_a_refusal_and_carry_on(self):
        why = []

        def hello(app):
            try:
                app.notify.beep()
            except Refusal as refusal:
                why.append(refusal.code)

        tool = (
            self.bench.hello()
            .run("hello", 7)
            .app(
                '{"jsonrpc":"2.0","id":1,"error":{"code":-32004,"message":"not available right now"}}'
            )
            .goodbye()
            .tool(lambda t: t.command("hello", hello))
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(why, [RefusalCode.UNAVAILABLE])
        self.assertEqual(self.bench.written()[-1], result(7, {}))

    def test_a_command_that_will_not_run_says_why(self):
        def hello(app):
            raise CommandRefused("nothing is selected")

        tool = (
            self.bench.hello()
            .run("hello", 3)
            .run("missing", 4)
            .app('{"jsonrpc":"2.0","id":5,"method":"island/draw"}')
            .goodbye()
            .tool(lambda t: t.command("hello", hello))
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(
            self.bench.written()[1:],
            [
                failure(3, -32010, "nothing is selected"),
                failure(4, -32602, "no such command"),
                failure(5, -32601, "method not found"),
            ],
        )

    def test_what_comes_while_a_handler_waits_is_handled_after_it(self):
        order = []

        def first(app):
            app.notify.beep()
            order.append("first in " + app.language)

        def second(app):
            app.notify.beep()
            order.append("second in " + app.language)

        def build(tool):
            tool.command("first", first)
            tool.command("second", second)

        tool = (
            self.bench.hello()
            .run("first", 2)
            .app(
                '{"jsonrpc":"2.0","method":"language/changed","params":{"language":"fr"}}'
            )
            .run("second", 3)
            .app('{"jsonrpc":"2.0","id":1,"result":{}}')
            .app('{"jsonrpc":"2.0","id":2,"result":{}}')
            .goodbye()
            .tool(build)
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(
            order, ["first in de-DE", "second in fr"], "kept in the order it came"
        )
        answers = [m["id"] for m in self.bench.written() if "result" in m]
        self.assertEqual(answers, ["hello", 2, 3])

    def test_goodbye_while_a_handler_waits_ends_the_wait(self):
        thrown = []

        def hello(app):
            try:
                app.notify.beep()
            except AppUnreachable as error:
                thrown.append(error.reason)
                raise

        tool = (
            self.bench.hello()
            .run("hello", 2)
            .goodbye()
            .tool(lambda t: t.command("hello", hello))
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(thrown, ["link_closed"])
        last = self.bench.written()[-1]
        self.assertEqual((last["id"], last["error"]["code"]), (2, -32010))

    def test_the_link_ending_ends_the_wait_and_the_loop(self):
        thrown = []

        def hello(app):
            try:
                app.notify.beep()
            except AppUnreachable as error:
                thrown.append(error.reason)

        tool = (
            self.bench.hello().run("hello", 2).tool(lambda t: t.command("hello", hello))
        )
        self.assertEqual(
            tool.serve(), 0, "the app going away is not the tool's failure"
        )
        self.assertEqual(thrown, ["link_closed"])

    def test_a_call_gives_up_when_no_answer_comes(self):
        # A pipe, so that the link stays open with nothing on it.
        reading, writing = os.pipe()
        lines = (
            '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersions":["1"],"language":"en","dataFolder":"/tmp"}}\n'
            '{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"hello"}}\n'
        )
        os.write(writing, lines.encode())
        output = os.open(
            os.path.join(self.bench.folder, "to-app"), os.O_WRONLY | os.O_CREAT
        )
        self.bench.ends = [reading, output]
        tool = Tool(version="1", input=reading, output=output)
        tool.answer_seconds = 0.05
        thrown = []

        def hello(app):
            try:
                app.notify.beep()
            except AppUnreachable as error:
                thrown.append(error)
            # The app goes away, which ends the loop.
            os.close(writing)

        tool.command("hello", hello)
        started = time.monotonic()
        self.assertEqual(tool.serve(), 0)
        self.assertEqual([(e.reason, e.seconds) for e in thrown], [("no_answer", 0.05)])
        self.assertLess(time.monotonic() - started, 5)

    def test_the_newest_version_both_speak_is_picked(self):
        for offered, picked in [
            ('["1","2"]', "2"),
            ('["1"]', "1"),
            ('["2","1"]', "2"),
            ('["2","3"]', "2"),
        ]:
            with self.subTest(offered):
                bench = Bench()
                tool = bench.hello(offered).goodbye().tool()
                self.assertEqual(tool.serve(), 0)
                self.assertEqual(
                    bench.written()[0]["result"],
                    {"protocolVersion": picked, "toolVersion": "9.9.9"},
                )
                bench.done()

    def test_a_version_the_tool_does_not_speak_is_refused(self):
        ran = []
        tool = (
            self.bench.hello('["3"]')
            .run("hello", 2)
            .goodbye()
            .tool(lambda t: t.command("hello", lambda app: ran.append(True)))
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(ran, [])
        self.assertEqual(
            self.bench.written(),
            [
                failure("hello", -32602, "this tool speaks protocols 1 and 2 only"),
                failure(2, -32600, "initialize comes first"),
            ],
        )

    def test_notices_reach_their_handlers_and_the_tools_own_are_written_after_hello(
        self,
    ):
        changed, language = [], []

        def start(app):
            app.commands.state(runnable=["hello"])
            app.log(message="started")

        def build(tool):
            tool.on_start = start
            tool.on_preferences_changed = lambda app, values: changed.append(values)
            tool.on_language_changed = lambda app: language.append(app.language)

        tool = (
            self.bench.hello()
            .app("this line is not a message")
            .app(
                '{"jsonrpc":"2.0","method":"preferences/changed","params":{"values":{"project":"web"}}}'
            )
            .app(
                '{"jsonrpc":"2.0","method":"language/changed","params":{"language":"ja"}}'
            )
            .goodbye()
            .tool(build)
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(changed, [{"project": "web"}])
        self.assertEqual(language, ["ja"])
        self.assertEqual(
            self.bench.written()[1:],
            [
                {
                    "jsonrpc": "2.0",
                    "method": "commands/state",
                    "params": {"runnable": ["hello"]},
                },
                {"jsonrpc": "2.0", "method": "log", "params": {"message": "started"}},
            ],
            "after the answer to initialize, never before it",
        )

    def test_an_async_handler_is_refused_not_answered_before_its_work_is_done(self):
        async def later(app):
            pass

        tool = (
            self.bench.hello()
            .run("later", 2)
            .goodbye()
            .tool(lambda t: t.command("later", later))
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(self.bench.written()[-1]["error"]["code"], -32010)

    def test_the_tools_own_standard_input_a_pipe_is_read_with_a_time_limit_too(self):
        # The real path: a tool started with a pipe on its standard input, as
        # the app starts it, whose call gets no answer.
        program = "\n".join(
            [
                "import sys",
                f"sys.path.insert(0, {os.path.dirname(HERE)!r})",
                "from vitruvian_tool_kit import Tool, AppUnreachable",
                "tool = Tool(version='1')",
                "tool.answer_seconds = 0.05",
                "def hello(app):",
                "    try:",
                "        app.notify.beep()",
                "    except AppUnreachable as error:",
                "        app.log(message=error.reason)",
                "tool.command('hello', hello)",
                "tool.run()",
            ]
        )
        child = subprocess.Popen(
            [sys.executable, "-c", program],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
        )
        child.stdin.write(
            b'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersions":["1"],"language":"en","dataFolder":"/tmp"}}\n'
            b'{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"hello"}}\n'
        )
        child.stdin.flush()
        out = b""
        while b'"log"' not in out:
            line = child.stdout.readline()
            if not line:
                break
            out += line
        child.stdin.close()
        out += child.stdout.read()
        self.assertEqual(child.wait(timeout=10), 0)
        self.assertIn(
            b'{"jsonrpc":"2.0","method":"log","params":{"message":"no_answer"}}', out
        )
        self.assertIn(b'{"jsonrpc":"2.0","id":2,"result":{}}', out)
        child.stdout.close()


if __name__ == "__main__":
    unittest.main()


def open_(panel, id):
    return '{"jsonrpc":"2.0","id":%d,"method":"ui/open","params":{"panel":"%s"}}' % (
        id,
        panel,
    )


def tap(panel, block, id):
    return (
        '{"jsonrpc":"2.0","id":%d,"method":"ui/event","params":{"panel":"%s","block":"%s","event":"tap"}}'
        % (id, panel, block)
    )


def close(panel):
    return '{"jsonrpc":"2.0","method":"ui/close","params":{"panel":"%s"}}' % panel


def tree_of(message):
    return message.get("result", {}).get("tree")


def page(words):
    return tree(text(words))


class PanelTests(unittest.TestCase):
    """The Swift kit's PanelTests, test for test."""

    def setUp(self):
        self.bench = Bench()

    def tearDown(self):
        self.bench.done()

    def test_a_panel_is_opened_acted_in_and_closed(self):
        count = [0]
        seen = []
        handle = []

        def on_event(app, panel, event):
            seen.append(event)
            if event.block != "add":
                return PanelAnswer.keep()
            count[0] += 1
            return PanelAnswer.page(page(f"Pressed {count[0]} times"))

        def build(tool):
            handle.append(
                tool.panel(
                    "counter",
                    on_open=lambda app, panel: page(f"Pressed {count[0]} times"),
                    on_event=on_event,
                )
            )

        tool = (
            self.bench.hello('["1","2"]')
            .app(open_("counter", 2))
            .app(tap("counter", "add", 3))
            .app(tap("counter", "nothing", 4))
            .app(close("counter"))
            .goodbye()
            .tool(build)
        )
        self.assertEqual(tool.serve(), 0)
        written = self.bench.written()
        self.assertEqual(
            written[0],
            result("hello", {"protocolVersion": "2", "toolVersion": "9.9.9"}),
        )
        self.assertEqual(
            tree_of(written[1]),
            {"blocks": [{"type": "text", "text": "Pressed 0 times"}]},
        )
        self.assertEqual(
            tree_of(written[2]),
            {"blocks": [{"type": "text", "text": "Pressed 1 times"}]},
        )
        self.assertEqual(written[3], result(4, {"keep": True}))
        self.assertEqual(seen, [PanelEvent("add", "tap"), PanelEvent("nothing", "tap")])
        self.assertFalse(handle[0].is_open, "ui/close closes it")

    def test_a_page_is_sent_unprompted_only_while_the_panel_is_open(self):
        sent = []

        def build(tool):
            panel = tool.panel(
                "counter", on_open=lambda app, panel: tree(heading("Counter"))
            )
            tool.command(
                "refresh", lambda app: sent.append(panel.render(page("Later")))
            )

        tool = (
            self.bench.hello('["1","2"]')
            .run("refresh", 2)
            .app(open_("counter", 3))
            .run("refresh", 4)
            .app(close("counter"))
            .run("refresh", 5)
            .goodbye()
            .tool(build)
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(sent, [False, True, False])
        renders = [m for m in self.bench.written() if m.get("method") == "ui/render"]
        self.assertEqual(
            renders,
            [
                {
                    "jsonrpc": "2.0",
                    "method": "ui/render",
                    "params": {
                        "panel": "counter",
                        "tree": {"blocks": [{"type": "text", "text": "Later"}]},
                    },
                }
            ],
        )

    def test_what_is_not_a_panel_of_the_tools_is_refused(self):
        tool = (
            self.bench.hello('["1","2"]')
            .app(open_("nowhere", 2))
            .app(tap("counter", "add", 3))
            .goodbye()
            .tool(lambda t: t.panel("counter", on_open=lambda app, panel: None))
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(
            self.bench.written()[1:],
            [
                failure(2, -32602, "no such panel"),
                failure(3, -32602, "the panel is not open"),
            ],
        )

    def test_an_answer_may_open_a_window_or_reply_and_the_badge_is_a_request(self):
        def on_open(app, panel):
            panel.badge(count=2)
            return None

        tool = (
            self.bench.hello('["1","2"]')
            .app(open_("deploys", 2))
            .app(tap("deploys", "log", 3))
            .app('{"jsonrpc":"2.0","id":1,"result":{}}')
            .goodbye()
            .tool(
                lambda t: t.panel(
                    "deploys",
                    on_open=on_open,
                    on_event=lambda app, panel, event: PanelAnswer.open("log"),
                )
            )
        )
        self.assertEqual(tool.serve(), 0)
        written = self.bench.written()
        self.assertEqual(
            written[1],
            {"jsonrpc": "2.0", "id": 1, "method": "ui/badge", "params": {"count": 2}},
        )
        self.assertEqual(written[2], result(2, {}), "a page given as none is no tree")
        self.assertEqual(written[3], result(3, {"open": "log"}))

    def test_a_web_panels_calls_are_the_tools_own_or_passed_to_the_app(self):
        def bridge(id, call):
            return (
                '{"jsonrpc":"2.0","id":%d,"method":"ui/event","params":{"panel":"dashboard","event":"bridge","value":%s}}'
                % (id, call)
            )

        def on_call(app, method, params):
            if method != "tool/count":
                raise Refusal(RPCErrorObject(code=-32601, message="method not found"))
            return {"count": params["by"]}

        def build(tool):
            panel = tool.panel("dashboard", on_open=lambda app, panel: None)
            panel.on_call = on_call

        tool = (
            self.bench.hello('["1","2"]')
            .app(open_("dashboard", 2))
            .app(
                bridge(
                    3,
                    '{"method":"notify/hud","params":{"icon":"checkmark","message":"Saved"}}',
                )
            )
            .app('{"jsonrpc":"2.0","id":1,"result":{}}')
            .app(bridge(4, '{"method":"tool/count","params":{"by":2}}'))
            .app(bridge(5, '{"method":"tool/other"}'))
            .app(bridge(6, '{"method":"initialize"}'))
            .goodbye()
            .tool(build)
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(
            self.bench.written()[2:],
            [
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "notify/hud",
                    "params": {"icon": "checkmark", "message": "Saved"},
                },
                result(3, {"reply": {}}),
                result(4, {"reply": {"count": 2}}),
                failure(5, -32601, "method not found"),
                failure(6, -32601, "method not found"),
            ],
            "a request of the app's is asked of the app as the tool's own; a method of the tool's goes to on_call",
        )

    def test_a_status_is_sent_to_an_app_that_has_it(self):
        shown = []

        def check(app):
            shown.append(
                app.status(
                    "busy", text="Checks are running", icon="arrow.triangle.branch"
                )
            )
            shown.append(app.status("none"))

        tool = (
            self.bench.hello('["1","2"]', features='["ui.status","ui.later"]')
            .run("check", 2)
            .app('{"jsonrpc":"2.0","id":1,"result":{}}')
            .app('{"jsonrpc":"2.0","id":2,"result":{}}')
            .goodbye()
            .tool(lambda t: t.command("check", check))
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(shown, [True, True])
        written = self.bench.written()
        self.assertEqual(len(written), 4)
        self.assertEqual(
            written[1],
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "ui/status",
                "params": {
                    "state": "busy",
                    "text": "Checks are running",
                    "icon": "arrow.triangle.branch",
                },
            },
        )
        self.assertEqual(
            written[2],
            {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "ui/status",
                "params": {"state": "none"},
            },
        )

    def test_a_status_sends_its_words_to_an_app_that_draws_them(self):
        shown = []
        start = datetime.fromtimestamp(1760450400.5, tz=timezone.utc)

        def check(app):
            shown.append(
                app.status("busy", text="Checks are running", activity="3", since=start)
            )

        tool = (
            self.bench.hello('["2"]', features='["ui.status","ui.status.activity"]')
            .run("check", 2)
            .app('{"jsonrpc":"2.0","id":1,"result":{}}')
            .goodbye()
            .tool(lambda t: t.command("check", check))
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(shown, [True])
        self.assertEqual(
            self.bench.written()[1],
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "ui/status",
                "params": {
                    "state": "busy",
                    "text": "Checks are running",
                    "activity": "3",
                    "since": 1760450400.5,
                },
            },
            "the words, and the start time in Unix seconds",
        )

    def test_a_status_sends_no_words_to_an_app_from_3_48(self):
        # 3.48 and 3.49 name `ui.status` and not its words: the status goes,
        # without them.
        shown = []

        def check(app):
            shown.append(
                app.status(
                    "busy",
                    text="Checks are running",
                    activity="3",
                    since=datetime.now(timezone.utc),
                )
            )

        tool = (
            self.bench.hello(
                '["2"]', features='["ui.status","ui.choice","preferences.options"]'
            )
            .run("check", 2)
            .app('{"jsonrpc":"2.0","id":1,"result":{}}')
            .goodbye()
            .tool(lambda t: t.command("check", check))
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(shown, [True])
        self.assertEqual(
            self.bench.written()[1]["params"],
            {"state": "busy", "text": "Checks are running"},
            "sends no words to an app from 3.48",
        )

    def test_a_status_with_words_writes_nothing_for_an_app_without_a_status(self):
        shown = []

        def build(tool):
            tool.answer_seconds = 0.2
            tool.command(
                "check",
                lambda app: shown.append(
                    app.status("busy", activity="3", since=datetime.now(timezone.utc))
                ),
            )

        tool = self.bench.hello('["1","2"]').run("check", 2).goodbye().tool(build)
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(shown, [False])
        self.assertEqual(len(self.bench.written()), 2)

    def test_a_status_writes_nothing_for_an_older_app(self):
        # An app before 3.48: its hello has no `features`. No answer is
        # scripted, so a request sent here would wait and then fail.
        shown = []

        def check(app):
            shown.append(app.status("failure", text="main is red"))

        def build(tool):
            tool.answer_seconds = 0.2
            tool.command("check", check)

        tool = self.bench.hello('["1","2"]').run("check", 2).goodbye().tool(build)
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(shown, [False], "the call says the status is not shown")
        self.assertEqual(
            self.bench.written(),
            [
                result("hello", {"protocolVersion": "2", "toolVersion": "9.9.9"}),
                result(2, {}),
            ],
            "and nothing was sent for it: only the two answers are on the link",
        )

    def test_a_status_writes_nothing_for_an_app_that_has_other_things(self):
        shown = []
        tool = (
            self.bench.hello('["2"]', features='["ui.choice"]')
            .run("check", 2)
            .goodbye()
            .tool(
                lambda t: t.command("check", lambda app: shown.append(app.status("ok")))
            )
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(shown, [False])
        self.assertEqual(len(self.bench.written()), 2)

    def test_supports_is_true_only_for_what_the_hello_listed(self):
        has = []

        def ask(app):
            has.extend(
                app.supports(name)
                for name in (
                    Feature.CHOICE,
                    Feature.PREFERENCE_OPTIONS,
                    Feature.STATUS,
                    "ui.later",
                    "ui.never",
                )
            )

        tool = (
            self.bench.hello(features='["ui.choice","preferences.options","ui.later"]')
            .run("ask", 2)
            .goodbye()
            .tool(lambda t: t.command("ask", ask))
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(has, [True, True, False, True, False])
        self.assertEqual(
            (
                Feature.STATUS,
                Feature.CHOICE,
                Feature.PREFERENCE_OPTIONS,
                Feature.STATUS_ACTIVITY,
            ),
            ("ui.status", "ui.choice", "preferences.options", "ui.status.activity"),
        )

    def test_an_app_that_says_nothing_has_none_of_them(self):
        has = []
        tool = (
            self.bench.hello()
            .run("ask", 2)
            .goodbye()
            .tool(
                lambda t: t.command(
                    "ask",
                    lambda app: has.extend(
                        app.supports(name)
                        for name in (
                            Feature.STATUS,
                            Feature.CHOICE,
                            Feature.PREFERENCE_OPTIONS,
                            Feature.STATUS_ACTIVITY,
                        )
                    ),
                )
            )
        )
        self.assertEqual(tool.serve(), 0)
        self.assertEqual(has, [False, False, False, False])

    def test_a_choice_is_built_as_the_protocols_example(self):
        options = [
            UIChoiceOption(value="green", title="Green"),
            UIChoiceOption(
                value="breathe green",
                title={"en": "Pulsing green", "de": "Pulsierendes Grün"},
            ),
        ]
        built = choice(
            "light",
            "green",
            options,
            title="Mouse when green",
            enabled=True,
            fallback="Mouse when green: Green",
        )
        with open(
            os.path.join(
                os.path.dirname(os.path.dirname(os.path.dirname(HERE))),
                "protocol",
                "examples",
                "messages.json",
            ),
            encoding="utf-8",
        ) as handle:
            examples = json.load(handle)["examples"]
        example = next(
            e
            for e in examples
            if e["about"] == "a page with a choice among fixed options"
        )["message"]["params"]["tree"]["blocks"][0]
        self.assertEqual(built.to_json(), example)

        # With no fallback given, the builder writes one: an app before
        # 3.48 draws it in the menu's place.
        self.assertEqual(
            choice("light", "green", options, title="Mouse when green").fallback,
            "Mouse when green: Green",
        )
        self.assertEqual(
            choice("light", "green", options).fallback,
            "Green",
            "with no title, the selected option's title alone",
        )
        self.assertEqual(
            choice(
                "light", "breathe green", options, title="Mouse when green"
            ).fallback,
            {
                "en": "Mouse when green: Pulsing green",
                "de": "Mouse when green: Pulsierendes Grün",
            },
            "in every language either text has",
        )
        self.assertEqual(
            choice("light", "typed by hand", options, title="Light").fallback,
            "Light: typed by hand",
            "a value that is no option's is written as it is",
        )
        self.assertEqual(
            PanelEvent("light", "change", "breathe green").text,
            "breathe green",
            "a pick arrives as the event a field's change is, with the option's value",
        )

    def test_a_page_is_written_as_the_blocks_it_holds(self):
        count = 12
        rows = ["web", "api"]
        page = tree(
            heading("Counter"),
            text(f"Pressed {count} times", style="secondary"),
            button("add", "Add one", style="prominent"),
            text("That is a lot", style="caption") if count > 9 else None,
            divider() if count > 99 else spacer(4),
            *[row(name, id=name) for name in rows],
            list_("deploys", [UIListRow(id="web", title="web 1.42.0")]),
            toggle("notify", "Tell me", True),
            field("name", title="Name", placeholder="Type and press Return"),
            progress(0.5),
            image("ui/logo.png", alt="Logo"),
            link("Dashboard", "https://example.com"),
        )
        self.assertEqual(
            [block.type for block in page.blocks],
            [
                "heading",
                "text",
                "button",
                "text",
                "spacer",
                "row",
                "row",
                "list",
                "toggle",
                "field",
                "progress",
                "image",
                "link",
            ],
        )
        self.assertEqual(page.blocks[2].id, "add")
        self.assertEqual(
            [block.id for block in page.blocks if block.id is not None],
            ["add", "web", "api", "deploys", "notify", "name"],
        )
        self.assertEqual(
            page.blocks[1].to_json(),
            {"type": "text", "text": "Pressed 12 times", "style": "secondary"},
        )
