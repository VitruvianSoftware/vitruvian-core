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

// Package ui writes a page for a tool that draws: one function for each of
// the fourteen kinds of block, and Tree of them. The Swift kit's page
// builders, in Go. What a block may carry beyond its words is an options
// struct, left out when there is none:
//
//	ui.Tree(
//		ui.Heading("Counter"),
//		ui.Text(fmt.Sprintf("Pressed %d times", count)),
//		ui.Button("add", "Add one", ui.ButtonOptions{Style: ui.Prominent}),
//		ui.If(count > 9, ui.Text("That is a lot", ui.TextOptions{Style: ui.Caption})),
//	)
//
// Any text is a string, or a map from a language tag to a string with
// English under en: toolkit.UIText.
package ui

import (
	"sort"
	"strings"

	"github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit"
)

// The styles of words, for TextOptions.
const (
	Body       = "body"
	Secondary  = "secondary"
	Caption    = "caption"
	Monospaced = "monospaced"
)

// The styles of a button, for ButtonOptions.
const (
	Plain       = "plain"
	Prominent   = "prominent"
	Destructive = "destructive"
)

// The kinds of a field, for FieldOptions.
const (
	FieldText   = "text"
	FieldNumber = "number"
	FieldSecret = "secret"
)

// Unknown is the value of a Progress that is under way and nobody knows
// how far.
const Unknown = -1.0

// Tree is a page as the blocks it holds, one under the other. A block that
// is nothing, as If gives for a false condition, is left out.
func Tree(blocks ...toolkit.UIBlock) toolkit.UITree {
	kept := make([]toolkit.UIBlock, 0, len(blocks))
	for _, block := range blocks {
		if block.Type != "" {
			kept = append(kept, block)
		}
	}
	return toolkit.UITree{Blocks: kept}
}

// If is block when ok, and nothing, which Tree leaves out, when not.
func If(ok bool, block toolkit.UIBlock) toolkit.UIBlock {
	if !ok {
		return toolkit.UIBlock{}
	}
	return block
}

// TextOptions is what Text may carry beyond its words.
type TextOptions struct {
	// Style is Body when left out.
	Style string
	// Lines is the most lines the words take, 1 to 10; 4 when left out.
	Lines int
}

// Text is words.
func Text(text toolkit.UIText, options ...TextOptions) toolkit.UIBlock {
	block := toolkit.TextBlock{Text: text}
	if len(options) > 0 {
		block.Style = some(options[0].Style)
		if options[0].Lines > 0 {
			block.Lines = &options[0].Lines
		}
	}
	return toolkit.UIBlock{Type: "text", Text: &block}
}

// HeadingOptions is what Heading may carry beyond its words.
type HeadingOptions struct {
	// Section makes the heading start a section of the page, which the app
	// may list for the person to jump to; one without is a sub-heading. An
	// app without toolkit.FeatureSections draws a plain heading, and the
	// conformance script's older app fails a page that sends it one, so ask
	// app.Supports(toolkit.FeatureSections) first.
	Section bool
}

// Heading is a heading, of two lines at most.
func Heading(text toolkit.UIText, options ...HeadingOptions) toolkit.UIBlock {
	block := toolkit.HeadingBlock{Text: text}
	if len(options) > 0 && options[0].Section {
		yes := true
		block.Section = &yes
	}
	return toolkit.UIBlock{Type: "heading", Heading: &block}
}

// RowOptions is what Row may carry beyond its title.
type RowOptions struct {
	// ID names the row; with one it can be tapped.
	ID string
	// Subtitle is a quieter line under the title.
	Subtitle toolkit.UIText
	// Icon is an SF Symbol name.
	Icon string
	// Trailing is a few words at the row's end, such as a time.
	Trailing toolkit.UIText
}

// Row is one line that stands alone. With an ID it can be tapped: the
// event tap.
func Row(title toolkit.UIText, options ...RowOptions) toolkit.UIBlock {
	block := toolkit.RowBlock{Title: title}
	var id *string
	if len(options) > 0 {
		id = some(options[0].ID)
		block.Subtitle = options[0].Subtitle
		block.Icon = some(options[0].Icon)
		block.Trailing = options[0].Trailing
	}
	return toolkit.UIBlock{Type: "row", ID: id, Row: &block}
}

// ButtonOptions is what Button may carry beyond its title.
type ButtonOptions struct {
	// Style is Plain when left out.
	Style string
	// Disabled draws it dimmed, and it cannot be pressed.
	Disabled bool
}

// Button is a button. Pressing it is the event tap.
func Button(id string, title toolkit.UIText, options ...ButtonOptions) toolkit.UIBlock {
	block := toolkit.ButtonBlock{Title: title}
	if len(options) > 0 {
		block.Style = some(options[0].Style)
		block.Enabled = enabled(options[0].Disabled)
	}
	return toolkit.UIBlock{Type: "button", ID: &id, Button: &block}
}

// ToggleOptions is what Toggle may carry beyond its title and state.
type ToggleOptions struct {
	// Disabled draws it dimmed, and it cannot be turned.
	Disabled bool
	// Help is a line or two under it that says what it does. An app without
	// toolkit.FeatureSections leaves it out, so send that app a Text after
	// the switch instead.
	Help toolkit.UIText
}

// Toggle is a switch. Turning it is the event toggle, with its new state.
func Toggle(id string, title toolkit.UIText, isOn bool, options ...ToggleOptions) toolkit.UIBlock {
	block := toolkit.ToggleBlock{Title: title, Value: isOn}
	if len(options) > 0 {
		block.Enabled = enabled(options[0].Disabled)
		block.Help = options[0].Help
	}
	return toolkit.UIBlock{Type: "toggle", ID: &id, Toggle: &block}
}

// FieldOptions is what Field may carry.
type FieldOptions struct {
	// Title says what the field is for, above it.
	Title toolkit.UIText
	// Value is the text in it.
	Value string
	// Placeholder shows while it is empty.
	Placeholder toolkit.UIText
	// Kind is FieldText when left out; FieldNumber takes digits, and
	// FieldSecret hides what is typed.
	Kind string
	// Help is a line or two under it that says what it is for, as a
	// Toggle's.
	Help toolkit.UIText
}

// Field is a field to type in. Return is the event submit; leaving it with
// other text is the event change, each with the text.
func Field(id string, options ...FieldOptions) toolkit.UIBlock {
	block := toolkit.FieldBlock{}
	if len(options) > 0 {
		block.Title = options[0].Title
		block.Value = some(options[0].Value)
		block.Placeholder = options[0].Placeholder
		block.Kind = some(options[0].Kind)
		block.Help = options[0].Help
	}
	return toolkit.UIBlock{Type: "field", ID: &id, Field: &block}
}

// List is rows, drawn together, at most 200. Tapping one is the event tap,
// with the row's id.
func List(id string, rows []toolkit.UIListRow) toolkit.UIBlock {
	if rows == nil {
		rows = []toolkit.UIListRow{}
	}
	return toolkit.UIBlock{Type: "list", ID: &id, List: &toolkit.ListBlock{Rows: rows}}
}

// ProgressOptions is what Progress may carry beyond its value.
type ProgressOptions struct {
	// Label says what is under way.
	Label toolkit.UIText
}

// Progress is how far something has got: value from 0 to 1, or Unknown
// when it is under way and nobody knows how far.
func Progress(value float64, options ...ProgressOptions) toolkit.UIBlock {
	block := toolkit.ProgressBlock{}
	if value >= 0 {
		block.Value = &value
	}
	if len(options) > 0 {
		block.Label = options[0].Label
	}
	return toolkit.UIBlock{Type: "progress", Progress: &block}
}

// ImageOptions is what Image may carry beyond its source.
type ImageOptions struct {
	// Alt says what the picture shows, for VoiceOver.
	Alt toolkit.UIText
	// Height is in points, up to 300; the app's own when left out.
	Height float64
}

// Image is a picture: a file in the tool's folder, as a path inside it, or
// the picture itself as a data: address of a PNG or JPEG.
func Image(source string, options ...ImageOptions) toolkit.UIBlock {
	block := toolkit.ImageBlock{Source: source}
	if len(options) > 0 {
		block.Alt = options[0].Alt
		if options[0].Height > 0 {
			block.Height = &options[0].Height
		}
	}
	return toolkit.UIBlock{Type: "image", Image: &block}
}

// Divider is a line between blocks.
func Divider() toolkit.UIBlock {
	return toolkit.UIBlock{Type: "divider", Divider: &toolkit.DividerBlock{}}
}

// Link is a link the app opens through its open service, so the manifest
// must list open in uses.
func Link(title toolkit.UIText, url string) toolkit.UIBlock {
	return toolkit.UIBlock{Type: "link", Link: &toolkit.LinkBlock{Title: title, URL: url}}
}

// Spacer is room between blocks: size in points, up to 40, and 8 when
// left out.
func Spacer(size ...float64) toolkit.UIBlock {
	block := toolkit.SpacerBlock{}
	if len(size) > 0 {
		block.Size = &size[0]
	}
	return toolkit.UIBlock{Type: "spacer", Spacer: &block}
}

// ChoiceOptions is what Choice may carry beyond its options.
type ChoiceOptions struct {
	// Title says what is being chosen, beside the menu.
	Title toolkit.UIText
	// Disabled draws it dimmed, and nothing can be picked.
	Disabled bool
	// Fallback is what an app that does not know the kind draws instead.
	// Left out, Choice writes one.
	Fallback toolkit.UIText
	// Help is a line or two under it that says what it does, as a Toggle's.
	Help toolkit.UIText
}

// Choice is a pop-up menu: one of a fixed list of options, at most 64, no
// two with one value. value is the selected option's. Picking one is the
// event change, read with PanelEvent.Text.
//
// An app before 3.48 does not know this kind and draws the fallback, which
// nobody can change. So ask app.Supports(toolkit.FeatureChoice) first, and
// send a Field to an app without it. With no Fallback given, one is
// written: the title, a colon and the selected option's title.
func Choice(id, value string, options []toolkit.UIChoiceOption, more ...ChoiceOptions) toolkit.UIBlock {
	if options == nil {
		options = []toolkit.UIChoiceOption{}
	}
	block := toolkit.ChoiceBlock{Value: value, Options: options}
	var fallback toolkit.UIText
	if len(more) > 0 {
		block.Title = more[0].Title
		block.Enabled = enabled(more[0].Disabled)
		block.Help = more[0].Help
		fallback = more[0].Fallback
	}
	if fallback == nil {
		fallback = saidPlainly(block)
	}
	return toolkit.UIBlock{Type: "choice", ID: &id, Fallback: fallback, Choice: &block}
}

// ChipsOptions is what Chips may carry beyond its options.
type ChipsOptions struct {
	// Title says what the options are, above the chips.
	Title toolkit.UIText
	// Disabled draws every chip dimmed, and none can be turned.
	Disabled bool
	// Help is a line or two under them that says what they do, as a
	// Toggle's.
	Help toolkit.UIText
	// Fallback is what an app that does not know the kind draws instead.
	// Left out, Chips writes one.
	Fallback toolkit.UIText
}

// Chips is a fixed list of options, at most 64, no two with one value, any
// number of them on at once. Turning one is the event change, read with
// PanelEvent.Values: the values of every option then on. An option whose
// Enabled is false is dimmed, and its Reason says why.
//
// An app without toolkit.FeatureChips does not know this kind and draws the
// fallback, which nobody can change. So ask
// app.Supports(toolkit.FeatureChips) first, and send a Toggle for each
// option to an app without it. With no Fallback given, one is written: the
// title, a colon and the titles of the options that are on.
func Chips(id string, options []toolkit.UIChipOption, more ...ChipsOptions) toolkit.UIBlock {
	if options == nil {
		options = []toolkit.UIChipOption{}
	}
	block := toolkit.ChipsBlock{Options: options}
	var fallback toolkit.UIText
	if len(more) > 0 {
		block.Title = more[0].Title
		block.Enabled = enabled(more[0].Disabled)
		block.Help = more[0].Help
		fallback = more[0].Fallback
	}
	if fallback == nil {
		fallback = listedPlainly(block)
	}
	return toolkit.UIBlock{Type: "chips", ID: &id, Fallback: fallback, Chips: &block}
}

// listedPlainly is what chips say, as words: the title, a colon and the
// titles of the options that are on, or those titles alone, in every
// language any of them has. A dash stands for none.
func listedPlainly(block toolkit.ChipsBlock) toolkit.UIText {
	var on []toolkit.UIText
	for _, option := range block.Options {
		if option.On {
			on = append(on, option.Title)
		}
	}
	said := func(language string) string {
		titles := "\u2014"
		if len(on) > 0 {
			words := make([]string, len(on))
			for index, text := range on {
				words[index] = wordsOf(text, language)
			}
			titles = strings.Join(words, ", ")
		}
		if block.Title == nil {
			return titles
		}
		return wordsOf(block.Title, language) + ": " + titles
	}
	texts := on
	if block.Title != nil {
		texts = append([]toolkit.UIText{block.Title}, on...)
	}
	languages := languagesIn(texts)
	if len(languages) == 0 {
		return said("en")
	}
	all := toolkit.LocalizedText{}
	for _, language := range languages {
		all[language] = said(language)
	}
	return all
}

// languagesIn is the languages any of these texts has, in order.
func languagesIn(texts []toolkit.UIText) []string {
	seen := map[string]bool{}
	for _, text := range texts {
		for language := range languagesOf(text) {
			seen[language] = true
		}
	}
	languages := make([]string, 0, len(seen))
	for language := range seen {
		languages = append(languages, language)
	}
	sort.Strings(languages)
	return languages
}

// saidPlainly is what a choice says, as words: the title, a colon and the
// selected option's title, or that title alone, in every language either
// has. A value that is no option's is written as it is.
func saidPlainly(block toolkit.ChoiceBlock) toolkit.UIText {
	var selected toolkit.UIText = block.Value
	for _, option := range block.Options {
		if option.Value == block.Value {
			selected = option.Title
			break
		}
	}
	if block.Title == nil {
		return selected
	}
	languages := languagesIn([]toolkit.UIText{block.Title, selected})
	if len(languages) == 0 {
		return wordsOf(block.Title, "en") + ": " + wordsOf(selected, "en")
	}
	said := toolkit.LocalizedText{}
	for _, language := range languages {
		said[language] = wordsOf(block.Title, language) + ": " + wordsOf(selected, language)
	}
	return said
}

// languagesOf is a text's entries by language, and nothing for a string.
func languagesOf(text toolkit.UIText) map[string]string {
	switch text := text.(type) {
	case toolkit.LocalizedText:
		return text
	case map[string]string:
		return text
	case map[string]any:
		found := map[string]string{}
		for language, words := range text {
			if words, ok := words.(string); ok {
				found[language] = words
			}
		}
		return found
	}
	return nil
}

// wordsOf is a text in a language: its own entry, else English; a string
// whatever the language.
func wordsOf(text toolkit.UIText, language string) string {
	if plain, ok := text.(string); ok {
		return plain
	}
	entries := languagesOf(text)
	if words, ok := entries[language]; ok {
		return words
	}
	return entries["en"]
}

// some is a pointer to a string that is there, and nil for an empty one.
func some(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}

// enabled is false when disabled, and nil, left out, when not.
func enabled(disabled bool) *bool {
	if !disabled {
		return nil
	}
	no := false
	return &no
}
