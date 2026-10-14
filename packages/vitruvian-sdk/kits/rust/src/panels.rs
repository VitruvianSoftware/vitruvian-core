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

//! A tool that draws: its panels, what the person did in one, how a
//! handler answers, and a page written as the blocks it holds. The Swift
//! kit's Panels.swift, in Rust.

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use serde_json::Value;

use crate::app::App;
use crate::error::{codes, ToolError};
use crate::generated::{
    methods, ButtonBlock, ChoiceBlock, DividerBlock, Error, FieldBlock, HeadingBlock, ImageBlock,
    LinkBlock, ListBlock, LocalizedText, ProgressBlock, RowBlock, SpacerBlock, TextBlock,
    ToggleBlock, UiBlock, UiBlockContent, UiChoiceOption, UiEventResult, UiListRow, UiRenderParams,
    UiText, UiTree,
};

/// What the person did in one of the tool's panels, as a handler sees it.
#[derive(Clone, Debug, PartialEq)]
pub struct PanelEvent {
    /// The block's id, as the page gave it. None for a web page's call.
    pub block: Option<String>,
    /// `tap`, `toggle`, `submit`, `change` or `bridge`.
    pub kind: String,
    /// What the event carries: [`PanelEvent::row`], [`PanelEvent::text`]
    /// and [`PanelEvent::is_on`] read it.
    pub value: Option<Value>,
}

impl PanelEvent {
    /// For a tap on a row of a list: the row's id.
    pub fn row(&self) -> Option<&str> {
        match self.kind.as_str() {
            "tap" => self.value.as_ref().and_then(Value::as_str),
            _ => None,
        }
    }

    /// For `submit` and `change`: the field's text. For the `change` of a
    /// `choice`: the picked option's value.
    pub fn text(&self) -> Option<&str> {
        match self.kind.as_str() {
            "submit" | "change" => self.value.as_ref().and_then(Value::as_str),
            _ => None,
        }
    }

    /// For `toggle`: the switch's new state.
    pub fn is_on(&self) -> Option<bool> {
        match self.kind.as_str() {
            "toggle" => self.value.as_ref().and_then(Value::as_bool),
            _ => None,
        }
    }
}

/// How a handler answers what the person did.
#[derive(Clone, Debug, PartialEq)]
pub enum PanelAnswer {
    /// The next page.
    Page(UiTree),
    /// The page stays as it is.
    Keep,
    /// One of the tool's window panels opens, by its id.
    Open(String),
    /// What a web panel's `window.vitruvian.call` gets back.
    Reply(Value),
}

impl PanelAnswer {
    /// The answer as the wire carries it.
    pub(crate) fn result(self) -> UiEventResult {
        match self {
            PanelAnswer::Page(tree) => UiEventResult {
                tree: Some(tree),
                ..UiEventResult::default()
            },
            PanelAnswer::Keep => UiEventResult {
                keep: Some(true),
                ..UiEventResult::default()
            },
            PanelAnswer::Open(panel) => UiEventResult {
                open: Some(panel),
                ..UiEventResult::default()
            },
            PanelAnswer::Reply(value) => UiEventResult {
                reply: Some(value),
                ..UiEventResult::default()
            },
        }
    }
}

/// Gives the first page when the person opens the panel; a web panel gives
/// none. Any error refuses the opening: [`ToolError::App`] as it is,
/// anything else as an internal error with its words.
pub(crate) type Opened = Box<dyn FnMut(&mut App<'_>, &Panel) -> Result<Option<UiTree>, ToolError>>;
/// Answers what the person did. Any error refuses the event, as for
/// [`Opened`].
pub(crate) type Acted =
    Box<dyn FnMut(&mut App<'_>, &Panel, PanelEvent) -> Result<PanelAnswer, ToolError>>;
/// A web panel's call of a method of the tool's own, one whose name starts
/// with `tool/`: the method, its params, and the reply.
pub(crate) type Called =
    Box<dyn FnMut(&mut App<'_>, &str, Option<Value>) -> Result<Value, ToolError>>;

/// A method of the tool's own, which a web page may call: its name starts
/// with this.
pub(crate) const TOOLS_OWN: &str = "tool/";

/// One of the tool's panels, as the manifest declares it: the handle
/// [`crate::Tool::panel`] gives back. It is cheap to clone, and a clone is
/// the same panel: keep one in a command's handler to send a page from
/// there. Use it from the thread that runs the tool, as everything of a
/// `Tool`.
#[derive(Clone)]
pub struct Panel(Rc<PanelCell>);

struct PanelCell {
    id: String,
    open: Cell<bool>,
    on_call: RefCell<Option<Called>>,
}

/// A panel as the tool keeps it: the handle and its two handlers.
pub(crate) struct PanelEntry {
    pub handle: Panel,
    pub on_open: Opened,
    pub on_event: Acted,
}

impl Panel {
    pub(crate) fn new(id: &str) -> Panel {
        Panel(Rc::new(PanelCell {
            id: id.to_string(),
            open: Cell::new(false),
            on_call: RefCell::new(None),
        }))
    }

    /// The id the manifest gives it.
    pub fn id(&self) -> &str {
        &self.0.id
    }

    /// True while the app has it open: from `ui/open` to `ui/close`.
    pub fn is_open(&self) -> bool {
        self.0.open.get()
    }

    pub(crate) fn set_open(&self, open: bool) {
        self.0.open.set(open);
    }

    /// Sends a new page for the panel, unprompted: `ui/render`. False, and
    /// nothing is sent, when the panel is not open. The app draws at most
    /// four pages a second for a panel; send fewer.
    pub fn render(&self, app: &mut App<'_>, tree: &UiTree) -> bool {
        if !self.is_open() {
            return false;
        }
        let params = UiRenderParams {
            panel: self.0.id.clone(),
            tree: tree.clone(),
        };
        app.state_mut().note(methods::UI_RENDER, &params)
    }

    /// Puts a count, or a dot, beside the tool in the island's Tools area:
    /// `ui/badge`. With neither, the badge goes. Needs `notify` in `uses`.
    pub fn badge(&self, app: &mut App<'_>, count: Option<i64>, dot: bool) -> Result<(), ToolError> {
        app.ui().badge(count, dot)
    }

    /// For a web panel: what its page's calls of the tool's own methods
    /// answer. With none, such a call is answered as a method not found. A
    /// call of a request the app does, such as `notify/hud`, is passed to
    /// the app as the tool's own, with no handler.
    pub fn on_call(
        &self,
        handler: impl FnMut(&mut App<'_>, &str, Option<Value>) -> Result<Value, ToolError> + 'static,
    ) {
        *self.0.on_call.borrow_mut() = Some(Box::new(handler));
    }

    /// A web page's call of a method of the tool's own, answered by
    /// `on_call`. The handler is taken out while it runs, so one that sets
    /// another is not torn from under itself.
    pub(crate) fn call(
        &self,
        app: &mut App<'_>,
        method: &str,
        params: Option<Value>,
    ) -> Result<Value, ToolError> {
        let Some(mut handler) = self.0.on_call.borrow_mut().take() else {
            return Err(ToolError::App(Error {
                code: codes::METHOD_NOT_FOUND,
                message: "method not found".to_string(),
                data: None,
            }));
        };
        let answer = handler(app, method, params);
        let mut slot = self.0.on_call.borrow_mut();
        if slot.is_none() {
            *slot = Some(handler);
        }
        answer
    }
}

// Writing a page: one function for each kind of block, and `tree!` of them.

/// What `tree!` takes as one of its items: a block, one being written, an
/// `Option` of either, which is left out when `None`, or a `Vec` of them.
pub trait IntoBlocks {
    /// Adds the blocks this is to a page.
    fn into_blocks(self, into: &mut Vec<UiBlock>);
}

impl IntoBlocks for UiBlock {
    fn into_blocks(self, into: &mut Vec<UiBlock>) {
        into.push(self);
    }
}

impl<T: IntoBlocks> IntoBlocks for Option<T> {
    fn into_blocks(self, into: &mut Vec<UiBlock>) {
        if let Some(block) = self {
            block.into_blocks(into);
        }
    }
}

impl<T: IntoBlocks> IntoBlocks for Vec<T> {
    fn into_blocks(self, into: &mut Vec<UiBlock>) {
        for block in self {
            block.into_blocks(into);
        }
    }
}

/// A page as the blocks it holds, one under the other. An item that is
/// `None` is left out, so a page may be written with
/// `(count > 9).then(|| text("That is a lot"))`:
///
/// ```
/// use vitruvian_tool_kit::{button, heading, text, tree};
/// let count = 12;
/// let page = tree![
///     heading("Counter"),
///     text(format!("Pressed {count} times")),
///     button("add", "Add one").style("prominent"),
///     (count > 9).then(|| text("That is a lot").style("caption")),
/// ];
/// assert_eq!(page.blocks.len(), 4);
/// ```
#[macro_export]
macro_rules! tree {
    ($($block:expr),* $(,)?) => {{
        let mut blocks: Vec<$crate::UiBlock> = Vec::new();
        $( $crate::IntoBlocks::into_blocks($block, &mut blocks); )*
        $crate::UiTree { blocks }
    }};
}

impl UiBlock {
    fn of(content: UiBlockContent) -> UiBlock {
        UiBlock {
            id: None,
            fallback: None,
            content,
        }
    }

    /// The block's name within the page, as the events it causes name it.
    pub fn id(mut self, id: impl Into<String>) -> UiBlock {
        self.id = Some(id.into());
        self
    }

    /// What an app that does not know this kind draws instead, as plain
    /// text.
    pub fn fallback(mut self, text: impl Into<UiText>) -> UiBlock {
        self.fallback = Some(text.into());
        self
    }
}

/// A block of one kind being written: its own fields are set with its
/// methods, and `tree!` takes it as it is.
macro_rules! writing {
    ($(#[$doc:meta])* $name:ident, $kind:ident, $block:ident) => {
        $(#[$doc])*
        #[derive(Clone, Debug, PartialEq)]
        pub struct $name(UiBlock);

        impl $name {
            fn own(&mut self) -> &mut $block {
                match &mut self.0.content {
                    UiBlockContent::$kind(block) => block,
                    _ => unreachable!("a {} block is a {}", stringify!($name), stringify!($kind)),
                }
            }

            /// The block's name within the page, as the events it causes
            /// name it.
            pub fn id(self, id: impl Into<String>) -> $name {
                $name(self.0.id(id))
            }

            /// What an app that does not know this kind draws instead, as
            /// plain text.
            pub fn fallback(self, text: impl Into<UiText>) -> $name {
                $name(self.0.fallback(text))
            }
        }

        impl From<$name> for UiBlock {
            fn from(writing: $name) -> UiBlock {
                writing.0
            }
        }

        impl IntoBlocks for $name {
            fn into_blocks(self, into: &mut Vec<UiBlock>) {
                into.push(self.0);
            }
        }
    };
}

writing!(
    /// Words, from [`text`].
    Text, Text, TextBlock
);
writing!(
    /// One line that stands alone, from [`row`].
    Row, Row, RowBlock
);
writing!(
    /// A button, from [`button`].
    Button, Button, ButtonBlock
);
writing!(
    /// A switch, from [`toggle`].
    Toggle, Toggle, ToggleBlock
);
writing!(
    /// A field to type in, from [`field`].
    Field, Field, FieldBlock
);
writing!(
    /// How far something has got, from [`progress`].
    Progress, Progress, ProgressBlock
);
writing!(
    /// A picture, from [`image`].
    Image, Image, ImageBlock
);

impl Text {
    /// `body` when left out; `secondary` and `caption` are quieter,
    /// `monospaced` is for code and logs.
    pub fn style(mut self, style: &str) -> Text {
        self.own().style = Some(style.to_string());
        self
    }

    /// The most lines the words take, 1 to 10; 4 when left out.
    pub fn lines(mut self, lines: i64) -> Text {
        self.own().lines = Some(lines);
        self
    }
}

impl Row {
    /// A quieter line under the title.
    pub fn subtitle(mut self, subtitle: impl Into<UiText>) -> Row {
        self.own().subtitle = Some(subtitle.into());
        self
    }

    /// An SF Symbol name.
    pub fn icon(mut self, icon: &str) -> Row {
        self.own().icon = Some(icon.to_string());
        self
    }

    /// A few words at the row's end, such as a time.
    pub fn trailing(mut self, trailing: impl Into<UiText>) -> Row {
        self.own().trailing = Some(trailing.into());
        self
    }
}

impl Button {
    /// `plain` when left out; `prominent` is the page's main action,
    /// `destructive` one that deletes.
    pub fn style(mut self, style: &str) -> Button {
        self.own().style = Some(style.to_string());
        self
    }

    /// False draws it dimmed, and it cannot be pressed.
    pub fn enabled(mut self, enabled: bool) -> Button {
        self.own().enabled = Some(enabled);
        self
    }
}

impl Toggle {
    /// False draws it dimmed, and it cannot be turned.
    pub fn enabled(mut self, enabled: bool) -> Toggle {
        self.own().enabled = Some(enabled);
        self
    }
}

impl Field {
    /// What it is for, above it.
    pub fn title(mut self, title: impl Into<UiText>) -> Field {
        self.own().title = Some(title.into());
        self
    }

    /// The text in it.
    pub fn value(mut self, value: impl Into<String>) -> Field {
        self.own().value = Some(value.into());
        self
    }

    /// What it shows while it is empty.
    pub fn placeholder(mut self, placeholder: impl Into<UiText>) -> Field {
        self.own().placeholder = Some(placeholder.into());
        self
    }

    /// `text` when left out; `number` takes digits, and `secret` hides
    /// what is typed.
    pub fn kind(mut self, kind: &str) -> Field {
        self.own().kind = Some(kind.to_string());
        self
    }
}

impl Progress {
    /// What is under way.
    pub fn label(mut self, label: impl Into<UiText>) -> Progress {
        self.own().label = Some(label.into());
        self
    }
}

impl Image {
    /// What the picture shows, for VoiceOver.
    pub fn alt(mut self, alt: impl Into<UiText>) -> Image {
        self.own().alt = Some(alt.into());
        self
    }

    /// Its height in points, up to 300; the app's own when left out.
    pub fn height(mut self, height: f64) -> Image {
        self.own().height = Some(height);
        self
    }
}

/// A pop-up menu being written, from [`choice`]. Unlike the other blocks
/// being written, it writes its own fallback when it joins a page, unless
/// one was given.
#[derive(Clone, Debug, PartialEq)]
pub struct Choice(UiBlock);

impl Choice {
    fn own(&mut self) -> &mut ChoiceBlock {
        match &mut self.0.content {
            UiBlockContent::Choice(block) => block,
            _ => unreachable!("a Choice block is a Choice"),
        }
    }

    /// What is being chosen, beside the menu.
    pub fn title(mut self, title: impl Into<UiText>) -> Choice {
        self.own().title = Some(title.into());
        self
    }

    /// False draws it dimmed, and nothing can be picked.
    pub fn enabled(mut self, enabled: bool) -> Choice {
        self.own().enabled = Some(enabled);
        self
    }

    /// What an app that does not know this kind draws instead, as plain
    /// text. Left out, one is written: the title, a colon and the selected
    /// option's title.
    pub fn fallback(self, text: impl Into<UiText>) -> Choice {
        Choice(self.0.fallback(text))
    }

    /// The block, with the fallback written when none was given.
    fn finished(mut self) -> UiBlock {
        if self.0.fallback.is_none() {
            let said = said_plainly(self.own());
            self.0.fallback = Some(said);
        }
        self.0
    }
}

impl From<Choice> for UiBlock {
    fn from(writing: Choice) -> UiBlock {
        writing.finished()
    }
}

impl IntoBlocks for Choice {
    fn into_blocks(self, into: &mut Vec<UiBlock>) {
        into.push(self.finished());
    }
}

/// What a choice says, as words: the title, a colon and the selected
/// option's title, or that title alone, in every language either has. A
/// value that is no option's is written as it is.
fn said_plainly(block: &ChoiceBlock) -> UiText {
    let selected = block
        .options
        .iter()
        .find(|option| option.value == block.value)
        .map(|option| option.title.clone())
        .unwrap_or_else(|| UiText::Plain(block.value.clone()));
    let Some(title) = &block.title else {
        return selected;
    };
    fn words<'a>(text: &'a UiText, language: &str) -> &'a str {
        match text {
            UiText::Plain(plain) => plain,
            UiText::Languages(entries) => entries
                .get(language)
                .or_else(|| entries.get("en"))
                .map(String::as_str)
                .unwrap_or(""),
        }
    }
    let mut said = LocalizedText::new();
    for text in [title, &selected] {
        if let UiText::Languages(entries) = text {
            for language in entries.keys() {
                said.insert(language.clone(), String::new());
            }
        }
    }
    if said.is_empty() {
        return UiText::Plain(format!(
            "{}: {}",
            words(title, "en"),
            words(&selected, "en")
        ));
    }
    for (language, line) in said.iter_mut() {
        *line = format!("{}: {}", words(title, language), words(&selected, language));
    }
    UiText::Languages(said)
}

/// A pop-up menu: one of a fixed list of options, at most 64, no two with
/// one value. `value` is the selected option's. Picking one is the event
/// `change`, read with [`PanelEvent::text`]. [`Choice::title`] says what is
/// being chosen.
///
/// An app before 3.48 does not know this kind and draws the fallback, which
/// nobody can change. So ask `app.supports(features::CHOICE)` first, and
/// send a [`field`] to an app without it.
pub fn choice(
    id: impl Into<String>,
    value: impl Into<String>,
    options: Vec<UiChoiceOption>,
) -> Choice {
    Choice(
        UiBlock::of(UiBlockContent::Choice(ChoiceBlock {
            value: value.into(),
            options,
            ..ChoiceBlock::default()
        }))
        .id(id),
    )
}

/// Words. [`Text::style`] and [`Text::lines`] say how they are drawn.
pub fn text(text: impl Into<UiText>) -> Text {
    Text(UiBlock::of(UiBlockContent::Text(TextBlock {
        text: text.into(),
        ..TextBlock::default()
    })))
}

/// A heading, of two lines at most.
pub fn heading(text: impl Into<UiText>) -> UiBlock {
    UiBlock::of(UiBlockContent::Heading(HeadingBlock { text: text.into() }))
}

/// One line that stands alone. With an [`Row::id`] it can be tapped: the
/// event `tap`.
pub fn row(title: impl Into<UiText>) -> Row {
    Row(UiBlock::of(UiBlockContent::Row(RowBlock {
        title: title.into(),
        ..RowBlock::default()
    })))
}

/// A button. Pressing it is the event `tap`.
pub fn button(id: impl Into<String>, title: impl Into<UiText>) -> Button {
    Button(
        UiBlock::of(UiBlockContent::Button(ButtonBlock {
            title: title.into(),
            ..ButtonBlock::default()
        }))
        .id(id),
    )
}

/// A switch. Turning it is the event `toggle`, with its new state.
pub fn toggle(id: impl Into<String>, title: impl Into<UiText>, is_on: bool) -> Toggle {
    Toggle(
        UiBlock::of(UiBlockContent::Toggle(ToggleBlock {
            title: title.into(),
            value: is_on,
            ..ToggleBlock::default()
        }))
        .id(id),
    )
}

/// A field to type in. Return is the event `submit`; leaving it with other
/// text is the event `change`, each with the text.
pub fn field(id: impl Into<String>) -> Field {
    Field(UiBlock::of(UiBlockContent::Field(FieldBlock::default())).id(id))
}

/// Rows, drawn together, at most 200. Tapping one is the event `tap`, with
/// the row's id.
pub fn list(id: impl Into<String>, rows: Vec<UiListRow>) -> UiBlock {
    UiBlock::of(UiBlockContent::List(ListBlock { rows })).id(id)
}

/// How far something has got: `value` from 0 to 1, or `None` when it is
/// under way and nobody knows how far.
pub fn progress(value: impl Into<Option<f64>>) -> Progress {
    Progress(UiBlock::of(UiBlockContent::Progress(ProgressBlock {
        value: value.into(),
        ..ProgressBlock::default()
    })))
}

/// A picture: a file in the tool's folder, as a path inside it, or the
/// picture itself as a `data:` address of a PNG or JPEG.
pub fn image(source: impl Into<String>) -> Image {
    Image(UiBlock::of(UiBlockContent::Image(ImageBlock {
        source: source.into(),
        ..ImageBlock::default()
    })))
}

/// A line between blocks.
pub fn divider() -> UiBlock {
    UiBlock::of(UiBlockContent::Divider(DividerBlock {}))
}

/// A link the app opens through its `open` service, so the manifest must
/// list `open` in `uses`.
pub fn link(title: impl Into<UiText>, url: impl Into<String>) -> UiBlock {
    UiBlock::of(UiBlockContent::Link(LinkBlock {
        title: title.into(),
        url: url.into(),
    }))
}

/// Room between blocks: `size` in points, up to 40, or `None` for 8.
pub fn spacer(size: impl Into<Option<f64>>) -> UiBlock {
    UiBlock::of(UiBlockContent::Spacer(SpacerBlock { size: size.into() }))
}
