# A tool in Rust

A tool with two commands, written with the Rust kit: `hello` shows a short
message, and `count` keeps a number in a preference and shows it. It is one
file, with two crates beside the kit: `serde` and `serde_json`, as Rust has
no JSON of its own.

```sh
vitruvian-tool init ~/hello-rust --id com.you.hello-rust --name "Hello" --publisher "You" --template rust
~/hello-rust/build.sh
vitruvian-tool run ~/hello-rust/tool --command hello --command count
```

The program, `src/main.rs`:

```rust file=samples/hello-rust/src/main.rs
use vitruvian_tool_kit::Tool;

fn main() {
    let mut tool = Tool::new("0.1.0");

    tool.command("hello", |app| {
        app.notify().hud("Hello from a Rust tool", "hand.wave")
    });

    tool.command("count", |app| {
        let next = app.storage().get("count")?.as_f64().unwrap_or(0.0) + 1.0;
        app.storage().set("count", next)?;
        app.notify().hud(&format!("Counted to {next}"), "number")
    });

    tool.run();
}
```

`build.sh` builds the program into `tool/bin/tool`, and `tool/` is the
folder you add in Vitruvian: Settings, Features, Tools from outside, Add a
Tool.

## Drawing

[`../hello-panel-rust`](../hello-panel-rust) is a tool of protocol 2,
written with the same kit: a counter the app draws in the island from blocks
the tool sends. The guide's "Drawing" says how. Its page is `tree!` of its
blocks, one function for each kind, and an item that is `None` is left out:

```rust file=samples/hello-panel-rust/src/main.rs
    /// The island page: what it says now.
    fn page(&self, app: &App<'_>) -> UiTree {
        tree![
            heading("Counter"),
            text(format!("Pressed {} times", self.count)),
            button("add", format!("Add {}", self.step())).style("prominent"),
            field("name")
                .title("Your name")
                .value(&self.name)
                .placeholder("Type it and press Return"),
            (!self.name.is_empty())
                .then(|| text(format!("Hello, {}", self.name)).style("secondary")),
            self.status_picker(app),
            app.supports(features::STATUS_ACTIVITY)
                .then(|| self.words_picker()),
        ]
    }
```
