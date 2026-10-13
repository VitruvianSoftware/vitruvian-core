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

package toolkit

// App is the app, as a handler sees it. Each call is one request of the
// protocol, grouped by the service the tool's manifest must list in `uses`
// for it. Any call can be refused: it then returns the failure the app
// answered with, an *Error, whose Code says which refusal it is. A handler
// that returns it has its command answered as refused.
//
// A tool may do any of this itself: it is a separate program with every
// permission the app has. These are for what is better done through the
// app.
type App struct {
	// Notify needs `notify` in the manifest's `uses`.
	Notify Notify
	// Open needs `open`.
	Open Open
	// Clipboard needs `clipboard.read` to read and `clipboard.write` to
	// write.
	Clipboard Clipboard
	// Keystrokes needs `keystrokes`.
	Keystrokes Keystrokes
	// Processes needs `processes`.
	Processes Processes
	// Storage needs `storage`.
	Storage Storage
	// UI is the tool's badge in the island, for a tool of protocol 2. Needs
	// `notify`.
	UI UI

	tool *Tool
}

func newApp(tool *Tool) *App {
	return &App{
		Notify:     Notify{tool},
		Open:       Open{tool},
		Clipboard:  Clipboard{tool},
		Keystrokes: Keystrokes{tool},
		Processes:  Processes{tool},
		Storage:    Storage{tool},
		UI:         UI{tool},
		tool:       tool,
	}
}

// Language is the language the app is in, as a tag such as en-US. It
// follows the person's changes by itself.
func (a *App) Language() string { return a.tool.language }

// DataFolder is the folder the tool may keep its own files in. It is also
// the folder the app starts the tool in.
func (a *App) DataFolder() string { return a.tool.dataFolder }

// Send sends any request of the protocol and reads its answer into
// result, which may be nil.
func (a *App) Send(method string, params, result any) error {
	return a.tool.call(method, params, result)
}

// SetRunnable says which commands can run now. Until the first time, all
// of them can. It is a notice: the app does not answer it.
func (a *App) SetRunnable(commands ...string) {
	if commands == nil {
		commands = []string{}
	}
	a.tool.note(MethodCommandsState, CommandsStateParams{Runnable: commands})
}

// Log writes a line to the tool's log in Settings. It is a notice.
func (a *App) Log(line string) {
	a.tool.note(MethodLog, LogParams{Message: line})
}

// Notify is the app's short on-screen message and its alert sound.
type Notify struct{ tool *Tool }

// HUD shows the app's short on-screen message. icon is an SF Symbol name.
func (n Notify) HUD(message, icon string) error {
	return n.tool.call(MethodNotifyHUD, NotifyHUDParams{Icon: icon, Message: message}, nil)
}

// Beep plays the alert sound.
func (n Notify) Beep() error {
	return n.tool.call(MethodNotifyBeep, Empty{}, nil)
}

// Open opens links.
type Open struct{ tool *Tool }

// URL opens a link. False when nothing could open it.
func (o Open) URL(url string) (bool, error) {
	var answer OpenURLResult
	err := o.tool.call(MethodOpenURL, OpenURLParams{URL: url}, &answer)
	return answer.Opened, err
}

// Clipboard reads and writes the clipboard's text.
type Clipboard struct{ tool *Tool }

// ReadText is the clipboard's text. ok is false when it holds none.
func (c Clipboard) ReadText() (text string, ok bool, err error) {
	var answer ClipboardReadTextResult
	if err := c.tool.call(MethodClipboardReadText, Empty{}, &answer); err != nil || answer.Text == nil {
		return "", false, err
	}
	return *answer.Text, true, nil
}

// WriteText replaces the clipboard with text. False when the clipboard
// would not take it.
func (c Clipboard) WriteText(text string) (bool, error) {
	var answer ClipboardWriteTextResult
	err := c.tool.call(MethodClipboardWriteText, ClipboardWriteTextParams{Text: text}, &answer)
	return answer.Written, err
}

// Keystrokes types into the app in front.
type Keystrokes struct{ tool *Tool }

// Paste pastes text into the app in front.
func (k Keystrokes) Paste(text string) error {
	return k.tool.call(MethodKeystrokesPaste, KeystrokesPasteParams{Text: text}, nil)
}

// PressMenuItem presses the menu item with one of these key equivalents in
// the app in front. False when it has none.
func (k Keystrokes) PressMenuItem(equivalents ...KeyEquivalent) (bool, error) {
	var answer KeystrokesPressMenuItemResult
	err := k.tool.call(MethodKeystrokesPressMenuItem, KeystrokesPressMenuItemParams{Equivalents: equivalents}, &answer)
	return answer.Pressed, err
}

// Processes ends processes, with the app's checks.
type Processes struct{ tool *Tool }

// Terminate ends a process: at once with force, else by asking it to quit.
func (p Processes) Terminate(pid int, name string, force bool) error {
	return p.tool.call(MethodProcessesTerminate, ProcessesTerminateParams{PID: pid, Name: name, Force: force}, nil)
}

// Storage reads and writes the preferences the manifest declares.
type Storage struct{ tool *Tool }

// Get is one preference's value: a string, a bool or a float64.
func (s Storage) Get(key string) (any, error) {
	var answer StorageGetResult
	err := s.tool.call(MethodStorageGet, StorageGetParams{Key: key}, &answer)
	return answer.Value, err
}

// Set saves one preference. value is a string, a bool or a number.
func (s Storage) Set(key string, value any) error {
	return s.tool.call(MethodStorageSet, StorageSetParams{Key: key, Value: value}, nil)
}

// UI is what a tool of protocol 2 puts beside itself in the island's Tools
// area. Its panels are the tool's own; this is the one call the app answers.
type UI struct{ tool *Tool }

// Badge puts a count, or a dot, beside the tool in the island's Tools area.
// count nil and dot false take the badge away.
func (u UI) Badge(count *int, dot bool) error {
	params := UIBadgeParams{Count: count}
	if dot {
		params.Dot = &dot
	}
	return u.tool.call(MethodUIBadge, params, nil)
}
