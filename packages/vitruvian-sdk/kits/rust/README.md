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

Rust 1.75 or later. Two dependencies, `serde` and `serde_json`: Rust has no
JSON in its standard library. MIT licence.
