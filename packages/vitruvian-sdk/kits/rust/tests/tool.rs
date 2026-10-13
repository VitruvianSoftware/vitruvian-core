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

//! The kit against a link made of a buffer each way: what the app will have
//! sent, written before the tool starts, and what the tool writes. The
//! input's end is the end of the link, so no test here can wait for long.
//! These are the Swift kit's ToolTests, one for one.

use std::cell::{Cell, RefCell};
use std::io::{self, Cursor, Read, Write};
use std::rc::Rc;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use vitruvian_tool_kit::{
    button, divider, field, heading, image, link, list, progress, row, spacer, text, toggle, tree,
    Error, PanelAnswer, PanelEvent, RefusalCode, Tool, ToolError, UiListRow, METHODS,
};

/// What the tool writes, kept where the test can read it.
#[derive(Clone, Default)]
struct Written(Rc<RefCell<Vec<u8>>>);

impl Write for Written {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.0.borrow_mut().extend_from_slice(bytes);
        Ok(bytes.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[derive(Default)]
struct Bench {
    sent: String,
    written: Written,
}

impl Bench {
    /// One line the app sends.
    fn app(mut self, line: &str) -> Bench {
        self.sent.push_str(line);
        self.sent.push('\n');
        self
    }

    fn hello(self) -> Bench {
        self.hello_offering(r#"["1"]"#)
    }

    fn hello_offering(self, versions: &str) -> Bench {
        self.app(&format!(
            r#"{{"jsonrpc":"2.0","id":"hello","method":"initialize","params":{{"protocolVersions":{versions},"language":"de-DE","dataFolder":"/tmp/kit-data"}}}}"#
        ))
    }

    fn run(self, command: &str, id: i64) -> Bench {
        self.app(&format!(
            r#"{{"jsonrpc":"2.0","id":{id},"method":"command/run","params":{{"command":"{command}"}}}}"#
        ))
    }

    fn goodbye(self) -> Bench {
        self.app(r#"{"jsonrpc":"2.0","method":"shutdown"}"#)
    }

    fn open(self, panel: &str, id: i64) -> Bench {
        self.app(&format!(
            r#"{{"jsonrpc":"2.0","id":{id},"method":"ui/open","params":{{"panel":"{panel}"}}}}"#
        ))
    }

    fn tap(self, panel: &str, block: &str, id: i64) -> Bench {
        self.app(&format!(
            r#"{{"jsonrpc":"2.0","id":{id},"method":"ui/event","params":{{"panel":"{panel}","block":"{block}","event":"tap"}}}}"#
        ))
    }

    fn close(self, panel: &str) -> Bench {
        self.app(&format!(
            r#"{{"jsonrpc":"2.0","method":"ui/close","params":{{"panel":"{panel}"}}}}"#
        ))
    }

    /// Makes the tool over the two buffers.
    fn tool(&self) -> Tool {
        Tool::with_link(
            "9.9.9",
            Cursor::new(self.sent.clone().into_bytes()),
            self.written.clone(),
        )
    }

    /// What the tool wrote, a message a line.
    fn lines(&self) -> Vec<Value> {
        let written = self.written.0.borrow();
        String::from_utf8(written.clone())
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).expect("a line that is not JSON"))
            .collect()
    }
}

fn messages(lines: &[&str]) -> Vec<Value> {
    lines
        .iter()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect()
}

#[test]
fn every_request_a_tool_may_send_has_a_call() {
    // One command makes every call, and the app refuses each: what the
    // tool wrote names each request a tool may send, once, in order. A
    // request added to the protocol fails this until the kit has its call.
    let mut bench = Bench::default().hello().run("all", 100);
    for id in 1..=11 {
        bench = bench.app(&format!(
            r#"{{"jsonrpc":"2.0","id":{id},"error":{{"code":-32004,"message":"not available right now"}}}}"#
        ));
    }
    let bench = bench.goodbye();
    let mut tool = bench.tool();
    tool.command("all", |app| {
        let _ = app.notify().hud("Hello", "hand.wave");
        let _ = app.notify().beep();
        let _ = app.open().url("https://example.com");
        let _ = app.clipboard().read_text();
        let _ = app.clipboard().write_text("text");
        let _ = app.keystrokes().paste("text");
        let _ = app.keystrokes().press_menu_item(&[]);
        let _ = app.processes().terminate(4242, "node", false);
        let _ = app.storage().get("count");
        let _ = app.storage().set("count", 1);
        let _ = app.ui().badge(Some(2), false);
        Ok(())
    });
    assert_eq!(tool.serve(), 0);
    let lines = bench.lines();
    let asked: Vec<&str> = lines
        .iter()
        .filter_map(|message| message.get("method").and_then(Value::as_str))
        .collect();
    let wanted: Vec<&str> = METHODS
        .iter()
        .filter(|row| row.sender == "tool" && row.kind == "request")
        .map(|row| row.name)
        .collect();
    assert_eq!(asked, wanted, "each request once, in the protocol's order");
    assert_eq!(wanted.len(), 11);
}

#[test]
fn hello_a_command_and_goodbye() {
    let bench = Bench::default().hello().run("hello", 2).goodbye();
    let mut tool = bench.tool();
    let ran = Rc::new(Cell::new(0));
    let seen = Rc::new(RefCell::new(Vec::new()));
    let (counted, noted) = (ran.clone(), seen.clone());
    tool.command("hello", move |app| {
        counted.set(counted.get() + 1);
        *noted.borrow_mut() = vec![
            app.language().to_string(),
            app.data_folder().display().to_string(),
        ];
        Ok(())
    });
    assert_eq!(tool.serve(), 0);
    assert_eq!(ran.get(), 1);
    assert_eq!(
        *seen.borrow(),
        ["de-DE", "/tmp/kit-data"],
        "what the app said at hello is the handler's to read"
    );
    assert_eq!(
        bench.lines(),
        messages(&[
            r#"{"jsonrpc":"2.0","id":"hello","result":{"protocolVersion":"1","toolVersion":"9.9.9"}}"#,
            r#"{"jsonrpc":"2.0","id":2,"result":{}}"#,
        ])
    );
}

#[test]
fn a_handler_calls_the_app_and_reads_the_answer() {
    let bench = Bench::default()
        .hello()
        .run("copy", 2)
        .app(r#"{"jsonrpc":"2.0","id":1,"result":{"text":"from the clipboard"}}"#)
        .app(r#"{"jsonrpc":"2.0","id":2,"result":{}}"#)
        .goodbye();
    let mut tool = bench.tool();
    let read = Rc::new(RefCell::new(None));
    let kept = read.clone();
    tool.command("copy", move |app| {
        *kept.borrow_mut() = app.clipboard().read_text()?;
        app.notify().hud("Read it", "doc.on.clipboard")
    });
    assert_eq!(tool.serve(), 0);
    assert_eq!(read.borrow().as_deref(), Some("from the clipboard"));
    let written = bench.lines();
    assert_eq!(written.len(), 4);
    assert_eq!(
        written[1..],
        messages(&[
            r#"{"jsonrpc":"2.0","id":1,"method":"clipboard/readText","params":{}}"#,
            r#"{"jsonrpc":"2.0","id":2,"method":"notify/hud","params":{"icon":"doc.on.clipboard","message":"Read it"}}"#,
            r#"{"jsonrpc":"2.0","id":2,"result":{}}"#,
        ]),
        "the command is answered last"
    );
}

#[test]
fn an_answer_to_another_request_is_not_taken_for_this_one() {
    // Two answers nobody waits for, as a call that gave up would leave
    // behind, come before the one the handler waits for.
    let bench = Bench::default()
        .hello()
        .run("copy", 2)
        .app(r#"{"jsonrpc":"2.0","id":98,"error":{"code":-32004,"message":"not available right now"}}"#)
        .app(r#"{"jsonrpc":"2.0","id":99,"result":{"text":"somebody else's"}}"#)
        .app(r#"{"jsonrpc":"2.0","id":1,"result":{"text":"mine"}}"#)
        .goodbye();
    let mut tool = bench.tool();
    let read = Rc::new(RefCell::new(None));
    let kept = read.clone();
    tool.command("copy", move |app| {
        *kept.borrow_mut() = app.clipboard().read_text()?;
        Ok(())
    });
    assert_eq!(tool.serve(), 0);
    assert_eq!(read.borrow().as_deref(), Some("mine"));
    assert_eq!(
        bench.lines().last(),
        Some(&json!({"jsonrpc":"2.0","id":2,"result":{}}))
    );
}

#[test]
fn a_refusal_the_handler_lets_through_refuses_the_command() {
    let bench = Bench::default()
        .hello()
        .run("hello", 7)
        .app(r#"{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"not listed in uses","data":{"service":"notify"}}}"#)
        .goodbye();
    let mut tool = bench.tool();
    tool.command("hello", |app| app.notify().hud("Hello", "hand.wave"));
    assert_eq!(tool.serve(), 0);
    assert_eq!(
        bench.lines().last(),
        Some(
            &json!({"jsonrpc":"2.0","id":7,"error":{"code":-32010,"message":"command refused",
            "data":{"code":-32001,"message":"not listed in uses","data":{"service":"notify"}}}})
        ),
        "the app's reason goes with it, for the log"
    );
}

#[test]
fn a_handler_may_catch_a_refusal_and_carry_on() {
    let bench = Bench::default()
        .hello()
        .run("hello", 7)
        .app(r#"{"jsonrpc":"2.0","id":1,"error":{"code":-32004,"message":"not available right now"}}"#)
        .goodbye();
    let mut tool = bench.tool();
    let why = Rc::new(Cell::new(None));
    let kept = why.clone();
    tool.command("hello", move |app| {
        if let Err(ToolError::App(refusal)) = app.notify().beep() {
            kept.set(RefusalCode::of(&refusal));
        }
        Ok(())
    });
    assert_eq!(tool.serve(), 0);
    assert_eq!(why.get(), Some(RefusalCode::Unavailable));
    assert_eq!(
        bench.lines().last(),
        Some(&json!({"jsonrpc":"2.0","id":7,"result":{}}))
    );
}

#[test]
fn a_command_that_will_not_run_says_why() {
    let bench = Bench::default()
        .hello()
        .run("hello", 3)
        .run("missing", 4)
        .app(r#"{"jsonrpc":"2.0","id":5,"method":"island/draw"}"#)
        .goodbye();
    let mut tool = bench.tool();
    tool.command("hello", |_| Err(ToolError::refused("nothing is selected")));
    assert_eq!(tool.serve(), 0);
    assert_eq!(
        bench.lines()[1..],
        messages(&[
            r#"{"jsonrpc":"2.0","id":3,"error":{"code":-32010,"message":"nothing is selected"}}"#,
            r#"{"jsonrpc":"2.0","id":4,"error":{"code":-32602,"message":"no such command"}}"#,
            r#"{"jsonrpc":"2.0","id":5,"error":{"code":-32601,"message":"method not found"}}"#,
        ])
    );
}

#[test]
fn what_comes_while_a_handler_waits_is_handled_after_it() {
    let bench = Bench::default()
        .hello()
        .run("first", 2)
        .app(r#"{"jsonrpc":"2.0","method":"language/changed","params":{"language":"fr"}}"#)
        .run("second", 3)
        .app(r#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
        .app(r#"{"jsonrpc":"2.0","id":2,"result":{}}"#)
        .goodbye();
    let mut tool = bench.tool();
    let order = Rc::new(RefCell::new(Vec::new()));
    for name in ["first", "second"] {
        let order = order.clone();
        tool.command(name, move |app| {
            app.notify().beep()?;
            order
                .borrow_mut()
                .push(format!("{name} in {}", app.language()));
            Ok(())
        });
    }
    assert_eq!(tool.serve(), 0);
    assert_eq!(
        *order.borrow(),
        ["first in de-DE", "second in fr"],
        "kept in the order it came"
    );
    let answered: Vec<Value> = bench
        .lines()
        .into_iter()
        .filter(|message| message.get("result").is_some())
        .map(|message| message["id"].clone())
        .collect();
    assert_eq!(answered, [json!("hello"), json!(2), json!(3)]);
}

#[test]
fn goodbye_while_a_handler_waits_ends_the_wait() {
    let bench = Bench::default().hello().run("hello", 2).goodbye();
    let mut tool = bench.tool();
    let thrown = Rc::new(RefCell::new(None));
    let kept = thrown.clone();
    tool.command("hello", move |app| {
        let outcome = app.notify().beep();
        *kept.borrow_mut() = outcome.clone().err();
        outcome
    });
    assert_eq!(tool.serve(), 0);
    assert_eq!(*thrown.borrow(), Some(ToolError::LinkClosed));
    let last = bench.lines().pop().unwrap();
    assert_eq!(last["id"], json!(2));
    assert_eq!(last["error"]["code"], json!(-32010));
}

#[test]
fn the_link_ending_ends_the_wait_and_the_loop() {
    let bench = Bench::default().hello().run("hello", 2);
    let mut tool = bench.tool();
    let thrown = Rc::new(RefCell::new(None));
    let kept = thrown.clone();
    tool.command("hello", move |app| {
        *kept.borrow_mut() = app.notify().beep().err();
        Ok(())
    });
    assert_eq!(
        tool.serve(),
        0,
        "the app going away is not the tool's failure"
    );
    assert_eq!(*thrown.borrow(), Some(ToolError::LinkClosed));
}

/// A link that stays open with nothing on it after its lines, until the
/// test lets it go: what a pipe from an app that says nothing is.
struct HeldOpen {
    lines: Cursor<Vec<u8>>,
    release: Receiver<()>,
}

impl Read for HeldOpen {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        let count = self.lines.read(buffer)?;
        if count == 0 {
            // Waits until the test drops its end.
            let _ = self.release.recv();
        }
        Ok(count)
    }
}

#[test]
fn a_call_gives_up_when_no_answer_comes() {
    let (release, held) = channel::<()>();
    let lines = concat!(
        r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersions":["1"],"language":"en","dataFolder":"/tmp"}}"#,
        "\n",
        r#"{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"hello"}}"#,
        "\n"
    );
    let input = HeldOpen {
        lines: Cursor::new(lines.as_bytes().to_vec()),
        release: held,
    };
    let mut tool = Tool::with_link("1", input, Written::default());
    tool.set_answer_timeout(Duration::from_millis(50));
    let thrown = Rc::new(RefCell::new(None));
    let kept = thrown.clone();
    let app_end: Rc<RefCell<Option<Sender<()>>>> = Rc::new(RefCell::new(Some(release)));
    tool.command("hello", move |app| {
        *kept.borrow_mut() = app.notify().beep().err();
        // The app goes away, which ends the loop.
        app_end.borrow_mut().take();
        Ok(())
    });
    let started = Instant::now();
    assert_eq!(tool.serve(), 0);
    assert_eq!(
        *thrown.borrow(),
        Some(ToolError::NoAnswer(Duration::from_millis(50)))
    );
    assert!(started.elapsed() < Duration::from_secs(5));
}

#[test]
fn the_newest_version_both_speak_is_picked() {
    for (offered, picked) in [
        (r#"["1","2"]"#, "2"),
        (r#"["1"]"#, "1"),
        (r#"["2","1"]"#, "2"),
        (r#"["2","3"]"#, "2"),
    ] {
        let bench = Bench::default().hello_offering(offered).goodbye();
        assert_eq!(bench.tool().serve(), 0);
        assert_eq!(
            bench.lines(),
            messages(&[&format!(
                r#"{{"jsonrpc":"2.0","id":"hello","result":{{"protocolVersion":"{picked}","toolVersion":"9.9.9"}}}}"#
            )]),
            "{offered}"
        );
    }
}

#[test]
fn a_version_the_tool_does_not_speak_is_refused() {
    let bench = Bench::default()
        .hello_offering(r#"["3"]"#)
        .run("hello", 2)
        .goodbye();
    let mut tool = bench.tool();
    let ran = Rc::new(Cell::new(false));
    let kept = ran.clone();
    tool.command("hello", move |_| {
        kept.set(true);
        Ok(())
    });
    assert_eq!(tool.serve(), 0);
    assert!(!ran.get());
    assert_eq!(
        bench.lines(),
        messages(&[
            r#"{"jsonrpc":"2.0","id":"hello","error":{"code":-32602,"message":"this tool speaks protocols 1 and 2 only"}}"#,
            r#"{"jsonrpc":"2.0","id":2,"error":{"code":-32600,"message":"initialize comes first"}}"#,
        ])
    );
}

#[test]
fn notices_reach_their_handlers_and_the_tools_own_are_written() {
    let bench = Bench::default()
        .hello()
        .app("this line is not a message")
        .app(r#"{"jsonrpc":"2.0","method":"preferences/changed","params":{"values":{"project":"web"}}}"#)
        .app(r#"{"jsonrpc":"2.0","method":"language/changed","params":{"language":"ja"}}"#)
        .goodbye();
    let mut tool = bench.tool();
    let changed = Rc::new(RefCell::new(Value::Null));
    let language = Rc::new(RefCell::new(String::new()));
    let (kept_values, kept_language) = (changed.clone(), language.clone());
    tool.on_start(|app| {
        app.set_runnable(&["hello"]);
        app.log("started");
    });
    tool.on_preferences_changed(move |_, values| {
        *kept_values.borrow_mut() = Value::Object(values.clone());
    });
    tool.on_language_changed(move |app| *kept_language.borrow_mut() = app.language().to_string());
    assert_eq!(tool.serve(), 0);
    assert_eq!(*changed.borrow(), json!({"project": "web"}));
    assert_eq!(*language.borrow(), "ja");
    assert_eq!(
        bench.lines()[1..],
        messages(&[
            r#"{"jsonrpc":"2.0","method":"commands/state","params":{"runnable":["hello"]}}"#,
            r#"{"jsonrpc":"2.0","method":"log","params":{"message":"started"}}"#,
        ]),
        "after the answer to initialize, never before it"
    );
}

/// An output whose reader has gone, as a pipe nobody reads any more.
struct Broken;

impl Write for Broken {
    fn write(&mut self, _: &[u8]) -> io::Result<usize> {
        Err(io::Error::from(io::ErrorKind::BrokenPipe))
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[test]
fn a_closed_link_is_an_end_not_a_crash() {
    // The first write fails; the tool stops reading and ends with 0, as the
    // Swift kit does. Rust's runtime ignores the broken-pipe signal, so a
    // real closed standard output is this same failed write.
    let bench = Bench::default().hello().run("hello", 2).run("hello", 3);
    let mut tool = Tool::with_link("1", Cursor::new(bench.sent.clone().into_bytes()), Broken);
    let ran = Rc::new(Cell::new(0));
    let counted = ran.clone();
    tool.command("hello", move |_| {
        counted.set(counted.get() + 1);
        Ok(())
    });
    assert_eq!(tool.serve(), 0);
    assert_eq!(ran.get(), 0, "nothing runs once the link has gone");
}

// A tool that draws: its panels opened, acted in, rendered to and closed,
// and a web panel's calls, against the same link of two buffers. These are
// the Swift kit's PanelTests, one for one.

fn tapped(block: &str) -> PanelEvent {
    PanelEvent {
        block: Some(block.to_string()),
        kind: "tap".to_string(),
        value: None,
    }
}

#[test]
fn a_panel_is_opened_acted_in_and_closed() {
    let bench = Bench::default()
        .hello_offering(r#"["1","2"]"#)
        .open("counter", 2)
        .tap("counter", "add", 3)
        .tap("counter", "nothing", 4)
        .close("counter")
        .goodbye();
    let mut tool = bench.tool();
    let count = Rc::new(Cell::new(0));
    let seen = Rc::new(RefCell::new(Vec::new()));
    let (opened, acted, noted) = (count.clone(), count.clone(), seen.clone());
    let handle = tool.panel(
        "counter",
        move |_app, _panel| Ok(Some(tree![text(format!("Pressed {} times", opened.get()))])),
        move |_app, _panel, event| {
            noted.borrow_mut().push(event.clone());
            if event.block.as_deref() != Some("add") {
                return Ok(PanelAnswer::Keep);
            }
            acted.set(acted.get() + 1);
            Ok(PanelAnswer::Page(tree![text(format!(
                "Pressed {} times",
                acted.get()
            ))]))
        },
    );
    assert_eq!(tool.serve(), 0);
    assert_eq!(
        bench.lines(),
        messages(&[
            r#"{"jsonrpc":"2.0","id":"hello","result":{"protocolVersion":"2","toolVersion":"9.9.9"}}"#,
            r#"{"jsonrpc":"2.0","id":2,"result":{"tree":{"blocks":[{"type":"text","text":"Pressed 0 times"}]}}}"#,
            r#"{"jsonrpc":"2.0","id":3,"result":{"tree":{"blocks":[{"type":"text","text":"Pressed 1 times"}]}}}"#,
            r#"{"jsonrpc":"2.0","id":4,"result":{"keep":true}}"#,
        ]),
        "a tool of the kit speaks protocol 2"
    );
    assert_eq!(*seen.borrow(), vec![tapped("add"), tapped("nothing")]);
    assert!(!handle.is_open(), "ui/close closes it");
}

#[test]
fn a_page_is_sent_unprompted_only_while_the_panel_is_open() {
    let bench = Bench::default()
        .hello_offering(r#"["1","2"]"#)
        .run("refresh", 2)
        .open("counter", 3)
        .run("refresh", 4)
        .close("counter")
        .run("refresh", 5)
        .goodbye();
    let mut tool = bench.tool();
    let sent = Rc::new(RefCell::new(Vec::new()));
    let noted = sent.clone();
    let panel = tool.panel(
        "counter",
        |_app, _panel| Ok(Some(tree![heading("Counter")])),
        |_app, _panel, _event| Ok(PanelAnswer::Keep),
    );
    tool.command("refresh", move |app| {
        noted
            .borrow_mut()
            .push(panel.render(app, &tree![text("Later")]));
        Ok(())
    });
    assert_eq!(tool.serve(), 0);
    assert_eq!(
        *sent.borrow(),
        [false, true, false],
        "render sends nothing for a panel that is not open"
    );
    let renders: Vec<Value> = bench
        .lines()
        .into_iter()
        .filter(|line| line["method"] == "ui/render")
        .collect();
    assert_eq!(
        renders,
        messages(&[
            r#"{"jsonrpc":"2.0","method":"ui/render","params":{"panel":"counter","tree":{"blocks":[{"type":"text","text":"Later"}]}}}"#,
        ])
    );
}

#[test]
fn what_is_not_a_panel_of_the_tools_is_refused() {
    let bench = Bench::default()
        .hello_offering(r#"["1","2"]"#)
        .open("nowhere", 2)
        .tap("counter", "add", 3)
        .goodbye();
    let mut tool = bench.tool();
    tool.panel(
        "counter",
        |_app, _panel| Ok(None),
        |_app, _panel, _event| Ok(PanelAnswer::Keep),
    );
    assert_eq!(tool.serve(), 0);
    assert_eq!(
        bench.lines()[1..],
        messages(&[
            r#"{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"no such panel"}}"#,
            r#"{"jsonrpc":"2.0","id":3,"error":{"code":-32602,"message":"the panel is not open"}}"#,
        ])
    );
}

#[test]
fn an_answer_may_open_a_window_or_reply_and_the_badge_is_a_request() {
    let bench = Bench::default()
        .hello_offering(r#"["1","2"]"#)
        .open("deploys", 2)
        .tap("deploys", "log", 3)
        .app(r#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
        .goodbye();
    let mut tool = bench.tool();
    tool.panel(
        "deploys",
        |app, panel| {
            panel.badge(app, Some(2), false)?;
            Ok(None)
        },
        |_app, _panel, _event| Ok(PanelAnswer::Open("log".to_string())),
    );
    assert_eq!(tool.serve(), 0);
    assert_eq!(
        bench.lines()[1..],
        messages(&[
            r#"{"jsonrpc":"2.0","id":1,"method":"ui/badge","params":{"count":2}}"#,
            r#"{"jsonrpc":"2.0","id":2,"result":{}}"#,
            r#"{"jsonrpc":"2.0","id":3,"result":{"open":"log"}}"#,
        ]),
        "a page given as none is no tree"
    );
}

#[test]
fn a_web_panels_calls_are_the_tools_own_or_passed_to_the_app() {
    fn bridge(id: i64, call: &str) -> String {
        format!(
            r#"{{"jsonrpc":"2.0","id":{id},"method":"ui/event","params":{{"panel":"dashboard","event":"bridge","value":{call}}}}}"#
        )
    }
    let bench = Bench::default()
        .hello_offering(r#"["1","2"]"#)
        .open("dashboard", 2)
        .app(&bridge(
            3,
            r#"{"method":"notify/hud","params":{"icon":"checkmark","message":"Saved"}}"#,
        ))
        .app(r#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
        .app(&bridge(4, r#"{"method":"tool/count","params":{"by":2}}"#))
        .app(&bridge(5, r#"{"method":"tool/other"}"#))
        .app(&bridge(6, r#"{"method":"initialize"}"#))
        .goodbye();
    let mut tool = bench.tool();
    let panel = tool.panel(
        "dashboard",
        |_app, _panel| Ok(None),
        |_app, _panel, _event| Ok(PanelAnswer::Keep),
    );
    panel.on_call(|_app, method, params| {
        if method != "tool/count" {
            return Err(ToolError::App(Error {
                code: -32601,
                message: "method not found".to_string(),
                data: None,
            }));
        }
        let by = params
            .and_then(|p| p.get("by").cloned())
            .unwrap_or(Value::Null);
        Ok(json!({ "count": by }))
    });
    assert_eq!(tool.serve(), 0);
    assert_eq!(
        bench.lines()[2..],
        messages(&[
            r#"{"jsonrpc":"2.0","id":1,"method":"notify/hud","params":{"icon":"checkmark","message":"Saved"}}"#,
            r#"{"jsonrpc":"2.0","id":3,"result":{"reply":{}}}"#,
            r#"{"jsonrpc":"2.0","id":4,"result":{"reply":{"count":2}}}"#,
            r#"{"jsonrpc":"2.0","id":5,"error":{"code":-32601,"message":"method not found"}}"#,
            r#"{"jsonrpc":"2.0","id":6,"error":{"code":-32601,"message":"method not found"}}"#,
        ]),
        "a request of the app's is asked of the app as the tool's own; a method of the tool's goes to on_call"
    );
}

#[test]
fn a_page_is_written_as_the_blocks_it_holds() {
    let count = 12;
    let rows = ["web", "api"];
    let page = tree![
        heading("Counter"),
        text(format!("Pressed {count} times")).style("secondary"),
        button("add", "Add one").style("prominent"),
        (count > 9).then(|| text("That is a lot").style("caption")),
        (count > 99).then(divider),
        (count <= 99).then(|| spacer(4.0)),
        rows.iter()
            .map(|name| row(*name).id(*name))
            .collect::<Vec<_>>(),
        list(
            "deploys",
            vec![UiListRow {
                id: "web".to_string(),
                title: "web 1.42.0".into(),
                ..UiListRow::default()
            }]
        ),
        toggle("notify", "Tell me", true),
        field("name")
            .title("Name")
            .placeholder("Type and press Return"),
        progress(0.5),
        image("ui/logo.png").alt("Logo"),
        link("Dashboard", "https://example.com"),
    ];
    let written = serde_json::to_value(&page).unwrap();
    let blocks = written["blocks"].as_array().unwrap();
    let types: Vec<&str> = blocks.iter().map(|b| b["type"].as_str().unwrap()).collect();
    assert_eq!(
        types,
        [
            "heading", "text", "button", "text", "spacer", "row", "row", "list", "toggle", "field",
            "progress", "image", "link"
        ]
    );
    let ids: Vec<&str> = blocks.iter().filter_map(|b| b["id"].as_str()).collect();
    assert_eq!(ids, ["add", "web", "api", "deploys", "notify", "name"]);
    assert_eq!(blocks[2]["style"], "prominent");
    assert_eq!(blocks[4]["size"], 4.0);
    assert_eq!(
        serde_json::to_value(divider()).unwrap(),
        json!({"type": "divider"}),
        "the twelfth kind"
    );
}
