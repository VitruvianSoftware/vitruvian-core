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

import "time"

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
	// UI is the tool's badge and its status in the island, for a tool of
	// protocol 2. The badge needs `notify`; the status needs nothing in
	// `uses`.
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

// What an app may have beyond the first release of a protocol version, by
// the name it gives at hello. Ask with App.Supports.
const (
	// FeatureStatus is ui/status: the tool's status on the closed island.
	FeatureStatus = "ui.status"
	// FeatureChoice is the choice block.
	FeatureChoice = "ui.choice"
	// FeaturePreferenceOptions is options on a text preference, drawn as a
	// pop-up menu.
	FeaturePreferenceOptions = "preferences.options"
	// FeatureStatusActivity is activity and since on ui/status: a few
	// words, or a count of seconds, beside the mark. From 3.50.
	FeatureStatusActivity = "ui.status.activity"
)

// Supports is whether this app has something a later release added to the
// protocol version: it named it at hello. False for an app that named
// nothing, as every app before 3.48 does. Ask before using a choice block,
// and send a field to an app without it.
func (a *App) Supports(feature string) bool { return a.tool.features[feature] }

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

// UI is what a tool of protocol 2 puts beside itself in the island: a badge
// in its Tools area, and a status on the closed island. Its panels are the
// tool's own; these are the calls the app answers.
type UI struct{ tool *Tool }

// What a status says, for UI.Status. The app draws each in its own style.
const (
	// StatusNone is no mark.
	StatusNone = "none"
	// StatusOK is all is well.
	StatusOK = "ok"
	// StatusBusy is something under way.
	StatusBusy = "busy"
	// StatusAttention is something that waits for the person.
	StatusAttention = "attention"
	// StatusFailure is something that failed.
	StatusFailure = "failure"
)

// StatusOptions is what Status may carry beyond its state.
type StatusOptions struct {
	// Text says what it means, in one short line, for VoiceOver and the
	// tooltip: a string, or a map from a language tag to a string.
	Text UIText
	// Icon is an SF Symbol name, drawn in place of the state's own glyph.
	Icon string
	// Activity is a few words for the closed island, beside the mark: a
	// string, or a map from a language tag to a string. Sent only to an app
	// that has FeatureStatusActivity.
	Activity UIText
	// Since is a start time the app counts the seconds from, when there
	// are no words. The zero time is none. Written as Unix seconds.
	Since time.Time
}

// Status sets the tool's status, a small mark the app draws on the closed
// island: ui/status. state is one of StatusNone, StatusOK, StatusBusy,
// StatusAttention and StatusFailure. Each one replaces the last; StatusNone
// takes it away; and it goes when the tool's program ends, so a tool that
// wants it to last starts with the app ("activation": ["onLaunch"]). The
// manifest must declare contributes.status: without it the app refuses, and
// the refusal is the error. It needs nothing in `uses`.
//
// Activity, a few words, and Since, a start time the app counts the seconds
// from, are drawn beside the mark while it is the one the closed island
// shows; the words win over the start time. Six characters or fewer, and a
// number is best. They show only on an app that has FeatureStatusActivity
// (3.50 and later): to an app without it the status is sent without them.
// The manifest's status must say "activity": true, or the app leaves them
// out.
//
// shown is false, and nothing is sent, when the app did not say it has
// ui.status: an app before 3.48 shows no status, and that is no error. It
// is true when the request was sent and answered; the person may still have
// switched the mark off.
func (u UI) Status(state string, options ...StatusOptions) (shown bool, err error) {
	if !u.tool.features[FeatureStatus] {
		return false, nil
	}
	params := UIStatusParams{State: state}
	if len(options) > 0 {
		params.Text = options[0].Text
		if options[0].Icon != "" {
			params.Icon = &options[0].Icon
		}
		// An app from before 3.50 is sent the status without its words.
		if u.tool.features[FeatureStatusActivity] {
			params.Activity = options[0].Activity
			if since := options[0].Since; !since.IsZero() {
				seconds := float64(since.Unix()) + float64(since.Nanosecond())/1e9
				params.Since = &seconds
			}
		}
	}
	if err := u.tool.call(MethodUIStatus, params, nil); err != nil {
		return false, err
	}
	return true, nil
}

// Badge puts a count, or a dot, beside the tool in the island's Tools area.
// count nil and dot false take the badge away.
func (u UI) Badge(count *int, dot bool) error {
	params := UIBadgeParams{Count: count}
	if dot {
		params.Dot = &dot
	}
	return u.tool.call(MethodUIBadge, params, nil)
}
