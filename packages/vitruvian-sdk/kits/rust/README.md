# vitruvian-tool-kit

Write a [Vitruvian](https://vitruviansoftware.dev) tool in Rust: declare
commands, handle them, call the app.

```rust
use vitruvian_tool_kit::Tool;

fn main() {
    let mut tool = Tool::new("0.1.0");
    tool.command("hello", |app| app.notify().hud("Hello", "hand.wave"));
    tool.run();
}
```

A tool is a program the Vitruvian app starts and talks to over its standard
input and output. It is trusted like an app: it runs as you, with every
permission Vitruvian has. The guide, the protocol and a sample are in
[the SDK's repository](https://github.com/VitruvianSoftware/vitruvian-sdk);
`vitruvian-tool init --template rust` starts a new tool.

A tool of protocol 2 draws: `tool.panel` says what a panel shows, and a page
is `tree!` of its blocks. `app.ui().status(status::BUSY, None, None)` sets the
small mark the app draws on the closed island, and `choice(id, value,
options)` is a pop-up menu on a page. Those two are newer than protocol 2
itself: `app.supports(features::CHOICE)` says whether this app has one. On an
app from before them `status` sends nothing and gives `Ok(false)`, and a
`choice` is drawn as its fallback text, so send a `field` there instead.

Rust 1.75 or later. Two dependencies, `serde` and `serde_json`: Rust has no
JSON in its standard library. MIT licence.
