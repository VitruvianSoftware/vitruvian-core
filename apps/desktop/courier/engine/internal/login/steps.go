// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package login

import (
	"fmt"

	"maunium.net/go/mautrix/bridgev2"
)

// The values of Step.Type.
const (
	StepDisplayAndWait = "display_and_wait" // show a QR code, emoji or code, then call Wait
	StepUserInput      = "user_input"       // ask for Fields, then call Submit
	StepCookies        = "cookies"          // sign in on a web page, collect Cookies, then call Submit
	StepComplete       = "complete"         // linked; the login is over
	StepUnsupported    = "unsupported"      // a step Courier can't do; Instructions says what to do instead. The login is over.
)

// Step is what the app is shown next. It is the wire shape: the engine's socket sends it as it is, and the
// app's LoginStep copies it. Optional parts are left out when empty.
type Step struct {
	LoginID      string      `json:"login_id"`
	StepID       string      `json:"step_id"`
	Type         string      `json:"type"`
	Instructions string      `json:"instructions,omitempty"`
	Display      *Display    `json:"display,omitempty"`
	Fields       []Field     `json:"fields,omitempty"`
	Cookies      *CookieStep `json:"cookies,omitempty"`
	RemoteName   string      `json:"remote_name,omitempty"` // on complete: what the network calls the account
	// AccountID, on complete, is the account the sign-in became (bridgev2's UserLoginID, a chat's rooms.login_id;
	// not LoginID, the sign-in's own: Ruling C16). OtherAccount says it isn't the account StartOptions.AccountID
	// asked to sign in again (the person scanned with another phone, say): that one is kept as it was, and the app
	// says another account was signed in (Ruling 11). Both are left out of the wire when empty.
	AccountID    string `json:"account_id,omitempty"`
	OtherAccount bool   `json:"other_account,omitempty"`
}

// Display is what a display_and_wait step shows.
type Display struct {
	Kind     string `json:"kind"` // qr | emoji | code
	Data     string `json:"data,omitempty"`
	ImageURL string `json:"image_url,omitempty"`
}

// Field is one value a user_input step asks for.
type Field struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Type        string   `json:"type"` // username, password, phone_number, email, 2fa_code, token, url, domain, select
	Pattern     string   `json:"pattern,omitempty"`
	Options     []string `json:"options,omitempty"`
	// DefaultValue is what a blank answer means; the app may pre-fill it.
	DefaultValue string `json:"default_value,omitempty"`
}

// CookieStep is a page to sign in on and the values to collect from it.
type CookieStep struct {
	URL        string        `json:"url"`
	UserAgent  string        `json:"user_agent,omitempty"`
	WaitForURL string        `json:"wait_for_url,omitempty"` // a pattern the page's address should match before the window closes
	ExtractJS  string        `json:"extract_js,omitempty"`   // a script that finds some or all of the values
	Fields     []CookieField `json:"fields"`
}

// CookieField is one value a cookies step collects, and where in the browser it can be read from.
type CookieField struct {
	ID       string         `json:"id"`
	Required bool           `json:"required"`
	Sources  []CookieSource `json:"sources"`
	// Pattern is a regular expression the (URL-decoded) value must match. Submit checks it; an app may too.
	Pattern string `json:"pattern,omitempty"`
}

// The values of CookieSource.Type.
const (
	SourceCookie        = "cookie"
	SourceLocalStorage  = "local_storage"
	SourceRequestHeader = "request_header"
	SourceRequestBody   = "request_body"
	SourceSpecial       = "special"
)

// CookieSource is one place a value can come from.
type CookieSource struct {
	Type         string `json:"type"` // cookie | local_storage | request_header | request_body | special
	Name         string `json:"name"`
	CookieDomain string `json:"cookie_domain,omitempty"`
}

// toStep maps a bridge's login step to the wire shape.
func toStep(loginID string, st *bridgev2.LoginStep) Step {
	out := Step{LoginID: loginID, StepID: st.StepID, Instructions: st.Instructions}
	switch st.Type {
	case bridgev2.LoginStepTypeDisplayAndWait:
		out.Type = StepDisplayAndWait
		if d := st.DisplayAndWaitParams; d != nil {
			switch d.Type {
			case bridgev2.LoginDisplayTypeQR, bridgev2.LoginDisplayTypeEmoji, bridgev2.LoginDisplayTypeCode:
				out.Display = &Display{Kind: string(d.Type), Data: d.Data, ImageURL: d.ImageURL}
			}
		}
	case bridgev2.LoginStepTypeUserInput:
		out.Type = StepUserInput
		if p := st.UserInputParams; p != nil {
			for _, f := range p.Fields {
				out.Fields = append(out.Fields, Field{
					ID: f.ID, Name: f.Name, Description: f.Description, Type: string(f.Type),
					Pattern: f.Pattern, Options: f.Options, DefaultValue: f.DefaultValue,
				})
			}
		}
	case bridgev2.LoginStepTypeCookies:
		out.Type = StepCookies
		c := st.CookiesParams
		if c == nil {
			c = &bridgev2.LoginCookiesParams{}
		}
		cs := &CookieStep{URL: c.URL, UserAgent: c.UserAgent, WaitForURL: c.WaitForURLPattern, ExtractJS: c.ExtractJS, Fields: []CookieField{}}
		for _, f := range c.Fields {
			cs.Fields = append(cs.Fields, toCookieField(f))
		}
		out.Cookies = cs
	case bridgev2.LoginStepTypeComplete:
		out.Type = StepComplete
		if p := st.CompleteParams; p != nil && p.UserLogin != nil && p.UserLogin.UserLogin != nil {
			out.RemoteName = p.UserLogin.RemoteName
		}
	default:
		return unsupported(loginID, st)
	}
	return out
}

// unsupported is the answer for a step Courier can't do (a passkey, a raw HTTP request, anything newer than
// this code). The advice names the step so a bug report can say which one it was.
func unsupported(loginID string, st *bridgev2.LoginStep) Step {
	why := "isn't something Courier can do yet"
	if st.Type == bridgev2.LoginStepTypeWebAuthn {
		why = "needs a passkey or security key, which Courier can't use yet"
	}
	return Step{
		LoginID: loginID, StepID: st.StepID, Type: StepUnsupported,
		Instructions: fmt.Sprintf("Courier can't do this sign-in step (type %q, id %q): it %s. "+
			"Choose a different sign-in method for this network if it offers one.", st.Type, st.StepID, why),
	}
}

func toCookieField(f bridgev2.LoginCookieField) CookieField {
	cf := CookieField{ID: f.ID, Required: f.Required, Pattern: f.Pattern, Sources: []CookieSource{}}
	for _, src := range f.Sources {
		cf.Sources = append(cf.Sources, CookieSource{Type: string(src.Type), Name: src.Name, CookieDomain: src.CookieDomain})
	}
	return cf
}
