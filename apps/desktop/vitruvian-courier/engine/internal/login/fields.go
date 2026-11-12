// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package login

import (
	"errors"
	"fmt"
	"slices"
	"strings"

	"maunium.net/go/mautrix/bridgev2"
)

// IsSecret reports whether a field's value must be kept out of sight and exactly as given: a password or token.
func IsSecret(fieldType string) bool {
	return fieldType == string(bridgev2.LoginInputFieldTypePassword) || fieldType == string(bridgev2.LoginInputFieldTypeToken)
}

// CheckField applies a field's rules to a value, as Submit will, and returns the cleaned value. It is for a front
// end that wants to say what is wrong before submitting. It knows only what the wire shape carries, so a custom
// check a connector attaches to its field is left to Submit. The errors never contain the value.
func CheckField(f Field, value string) (string, error) {
	return checkInput(bridgev2.LoginInputDataField{
		Type: bridgev2.LoginInputFieldType(f.Type), ID: f.ID, Name: f.Name, Description: f.Description,
		Pattern: f.Pattern, Options: f.Options, DefaultValue: f.DefaultValue,
	}, value)
}

// checkInput applies a field's rules to a value and returns the cleaned value to submit. A blank value takes the
// field's default. The errors never contain the value.
func checkInput(f bridgev2.LoginInputDataField, value string) (string, error) {
	if value == "" {
		value = f.DefaultValue
	}
	if value == "" {
		return "", errors.New("a value is needed")
	}
	if f.Type == bridgev2.LoginInputFieldTypeSelect && len(f.Options) > 0 && !slices.Contains(f.Options, value) {
		return "", fmt.Errorf("choose one of: %s", strings.Join(f.Options, ", "))
	}
	// The same cleaning and checks the bridge's own login commands apply: phone numbers and emails are cleaned,
	// and any other field is matched against its Pattern. A Pattern that doesn't compile fails every try, as it
	// does in the bridge's commands.
	f.FillDefaultValidate()
	cleaned, err := f.Validate(value)
	if err != nil {
		// A connector's own check could quote what it was given; the reason is not worth a leaked credential.
		if strings.Contains(err.Error(), value) {
			return "", errors.New("the value isn't accepted")
		}
		return "", err
	}
	return cleaned, nil
}

// checkFields cleans and checks the values for a user_input step. Plain values lose surrounding space; a
// password or token is kept exactly as given, since spaces can be part of one. Keys that aren't fields are
// dropped. Every field is needed, unless it has a default.
func checkFields(fields []bridgev2.LoginInputDataField, values map[string]string) (map[string]string, error) {
	out := make(map[string]string, len(fields))
	for _, f := range fields {
		raw := values[f.ID]
		if !IsSecret(string(f.Type)) {
			raw = strings.TrimSpace(raw)
		}
		v, err := checkInput(f, raw)
		if err != nil {
			name := f.Name
			if name == "" {
				name = f.ID
			}
			if IsSecret(string(f.Type)) {
				// Not even the reason: a check that fails on a secret says nothing about it.
				return nil, badValue(fmt.Errorf("%s isn't accepted", name))
			}
			return nil, badValue(fmt.Errorf("%s: %w", name, err))
		}
		out[f.ID] = v
	}
	return out, nil
}
