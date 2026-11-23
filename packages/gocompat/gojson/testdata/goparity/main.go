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

// Generates checked-in encoding/json parity vectors for //packages/gocompat/gojson.
package main

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math"
	"runtime"
	"sort"
	"strings"
)

func emit(tag, name string, cols ...string) {
	fmt.Printf("%s\t%s\t%s\n", tag, name, strings.Join(cols, "\t"))
}

func main() {
	fmt.Printf("# go_version: %s\n", runtime.Version())

	// 1. MSTR: control characters 0x00..=0x1f + special/HTML/UTF-8 cases.
	for b := byte(0); b < 0x20; b++ {
		inp := []byte{b}
		out, err := json.Marshal(string(inp))
		if err != nil {
			panic(err)
		}
		emit("MSTR", fmt.Sprintf("ctrl_%02x", b), hex.EncodeToString(inp), hex.EncodeToString(out))
	}
	strCases := []struct {
		name string
		raw  []byte
	}{
		{"empty", []byte("")},
		{"plain", []byte("hello world")},
		{"lt", []byte("<")},
		{"gt", []byte(">")},
		{"amp", []byte("&")},
		{"html", []byte("<a&b>")},
		{"quote", []byte(`"`)},
		{"backslash", []byte(`\`)},
		{"slash", []byte("/")},
		{"del", []byte{0x7f}},
		{"ls_ps_esc_text", []byte("\\u2028\\u2029")},
		{"ls_ps_utf8", []byte("\u2028\u2029")},
		{"valid_fffd", []byte("\ufffd")},
		{"mixed_valid", []byte("<x&y>\n\t\x7f\ufffd\u2028")},
	}
	for _, tc := range strCases {
		out, err := json.Marshal(string(tc.raw))
		if err != nil {
			panic(err)
		}
		emit("MSTR", tc.name, hex.EncodeToString(tc.raw), hex.EncodeToString(out))
	}

	// 2. MFERR: Go's json.Marshal rejects non-finite floats (NaN, +Inf, -Inf).
	for _, tc := range []struct {
		name string
		v    any
	}{
		{"f64_nan", math.NaN()},
		{"f64_pos_inf", math.Inf(1)},
		{"f64_neg_inf", math.Inf(-1)},
		{"f32_nan", float32(math.NaN())},
		{"f32_pos_inf", float32(math.Inf(1))},
		{"f32_neg_inf", float32(math.Inf(-1))},
	} {
		_, err := json.Marshal(tc.v)
		if err == nil {
			panic(fmt.Sprintf("expected error for %s", tc.name))
		}
		emit("MFERR", tc.name, hex.EncodeToString([]byte("ERR:"+err.Error())))
	}

	// 4. MI64 & MU64 extremes.
	for _, tc := range []struct {
		name string
		v    int64
	}{
		{"min", math.MinInt64},
		{"min_plus1", math.MinInt64 + 1},
		{"neg1", -1},
		{"zero", 0},
		{"one", 1},
		{"max_minus1", math.MaxInt64 - 1},
		{"max", math.MaxInt64},
	} {
		b, _ := json.Marshal(tc.v)
		emit("MI64", tc.name, fmt.Sprintf("%d", tc.v), string(b))
	}
	for _, tc := range []struct {
		name string
		v    uint64
	}{
		{"zero", 0},
		{"one", 1},
		{"max_minus1", math.MaxUint64 - 1},
		{"max", math.MaxUint64},
	} {
		b, _ := json.Marshal(tc.v)
		emit("MU64", tc.name, fmt.Sprintf("%d", tc.v), string(b))
	}

	// 5. MMAP: map key ordering and containers.
	mapEmit := func(name string, v any) {
		b, err := json.Marshal(v)
		if err != nil {
			panic(err)
		}
		emit("MMAP", name, "map", hex.EncodeToString(b))
	}
	mapEmit("empty_map", map[string]int64{})
	mapEmit("empty_slice", []int64{})
	mapEmit("ascii_keys", map[string]int64{"b": 1, "A": 2, "_": 3, "": 4, "a": 5})
	mapEmit("html_keys", map[string]string{">": "<", "&": "\u2028", "<": ">"})
	mapEmit("utf8_keys", map[string]int64{"\U0001f600": 1, "é": 2, "e": 3, "\u2028": 4})
	type Nested struct {
		A map[string]int64   `json:"a"`
		B []int64            `json:"b"`
		C []map[string]int64 `json:"c"`
		D map[string]int64   `json:"d"`
	}
	mapEmit("nested_containers", Nested{
		A: map[string]int64{},
		B: []int64{},
		C: []map[string]int64{{}},
		D: map[string]int64{"z": 1, "a": 2},
	})

	// 6. MIND: MarshalIndent(v, "", "  ") output.
	indEmit := func(name string, v any) {
		b, err := json.MarshalIndent(v, "", "  ")
		if err != nil {
			panic(err)
		}
		emit("MIND", name, hex.EncodeToString(b))
	}
	indEmit("empty_map", map[string]int64{})
	indEmit("empty_slice", []int64{})
	type IndS struct {
		A map[string]int64 `json:"a"`
		B []int64          `json:"b"`
		C []int64          `json:"c"`
	}
	indS := IndS{A: map[string]int64{}, B: []int64{}, C: []int64{1, 2}}
	indEmit("nested_empty", indS)
	type IndMix struct {
		HTML     string  `json:"html"`
		Num      int64   `json:"num"`
		EmptyArr [][]int `json:"empty_arr"`
	}
	indMix := IndMix{HTML: "<a&b>\u2028", Num: 1, EmptyArr: [][]int{{}}}
	indEmit("nested_mixed_html_int", indMix)

	// 7. SYN: checkValid / syntax errors & depth limit.
	synCases := []struct {
		name string
		inp  []byte
	}{
		{"empty", []byte("")},
		{"spaces", []byte("   ")},
		{"open_brace", []byte("{")},
		{"neg", []byte("-")},
		{"dot", []byte("1.")},
		{"exp", []byte("1e")},
		{"not_json", []byte("not json")},
		{"bad_key", []byte("{ this is not json")},
		{"trailing", []byte("{} x")},
		{"arr_trailing_comma", []byte("[1,]")},
		{"arr_space", []byte("[1 2]")},
		{"obj_missing_colon", []byte(`{"a" 1}`)},
		{"obj_missing_comma", []byte(`{"a":1 2}`)},
		{"bad_esc", []byte(`"\q"`)},
		{"bad_uhex", []byte(`"\u12x4"`)},
		{"raw_nl", []byte{'"', 'a', 0x0a, 'b', '"'}},
		{"single_quote", []byte("'")},
		{"leading_zero", []byte("01")},
		{"byte_00", []byte{0x00}},
		{"byte_07", []byte{0x07}},
		{"byte_7f", []byte{0x7f}},
		{"byte_80", []byte{0x80}},
		{"byte_a0", []byte{0xa0}},
		{"byte_a1", []byte{0xa1}},
		{"byte_ad", []byte{0xad}},
		{"byte_c3", []byte{0xc3}},
		{"byte_ff", []byte{0xff}},
		{"depth_10000", []byte(strings.Repeat("[", 10000) + strings.Repeat("]", 10000))},
		{"depth_10001", []byte(strings.Repeat("[", 10001) + strings.Repeat("]", 10001))},
		{"valid_complex", []byte(` {"a": [1, -0.5e+3, true, null, "\ud83d\ude00"]} `)},
	}
	for _, tc := range synCases {
		var v any
		err := json.Unmarshal(tc.inp, &v)
		res := "OK"
		if err != nil {
			res = "ERR:" + err.Error()
		}
		emit("SYN", tc.name, hex.EncodeToString(tc.inp), hex.EncodeToString([]byte(res)))
	}

	// 8. DEC: streaming Decoder edge cases.
	decCases := []struct {
		name string
		inp  []byte
	}{
		{"int", []byte("123")},
		{"int_trailing", []byte("123x")},
		{"obj_trailing", []byte("{}x")},
		{"arr_trailing", []byte("[]x")},
		{"dot_eof", []byte("1.")},
		{"exp_eof", []byte("1e")},
		{"neg_eof", []byte("-")},
		{"lit_eof", []byte("tru")},
		{"brace_eof", []byte("{")},
		{"bad_mid", []byte("{x")},
	}
	for _, tc := range decCases {
		var v any
		err := json.NewDecoder(strings.NewReader(string(tc.inp))).Decode(&v)
		res := "OK"
		if err != nil {
			res = "ERR:" + err.Error()
		}
		emit("DEC", tc.name, hex.EncodeToString(tc.inp), hex.EncodeToString([]byte(res)))
	}

	// 9. UNM_STR: invalid UTF-8 & lone surrogates.
	for _, tc := range []struct {
		name string
		inp  []byte
	}{
		{"bad_utf8_trunc", []byte{'"', 0xe2, 0x82, 'a', '"'}},
		{"bad_utf8_ff", []byte{'"', 0xff, '"'}},
		{"surrogates", []byte(`"\ud800x\udc00\ud83d\ude00"`)},
		{"escapes", []byte(`"\b\f\n\r\t\/\\\"\u003c"`)},
	} {
		var s string
		if err := json.Unmarshal(tc.inp, &s); err != nil {
			panic(err)
		}
		emit("UNM_STR", tc.name, hex.EncodeToString(tc.inp), hex.EncodeToString([]byte(s)))
	}

	// 10. UNM_STRUCT: ints, folding, slices, nested struct errors, map slices.
	for _, tc := range []struct {
		name string
		inp  string
	}{
		{"int_neg0", `{"N":-0}`},
		{"int_min", `{"N":-9223372036854775808}`},
		{"int_max", `{"N":9223372036854775807}`},
		{"int_1p0", `{"N":1.0}`},
		{"int_1p50", `{"N":1.50}`},
		{"int_1e2", `{"N":1e2}`},
		{"int_big", `{"N":99999999999999999999}`},
		{"int_1e400", `{"N":1e400}`},
		{"int_over_max", `{"N":9223372036854775808}`},
		{"int_under_min", `{"N":-9223372036854775809}`},
	} {
		type S struct{ N int }
		var s S
		err := json.Unmarshal([]byte(tc.inp), &s)
		res := fmt.Sprintf("OK:%d", s.N)
		if err != nil {
			res = "ERR:" + err.Error()
		}
		emit("UNM_STRUCT", tc.name, hex.EncodeToString([]byte(tc.inp)), hex.EncodeToString([]byte(res)))
	}

	for _, tc := range []struct {
		name string
		inp  string
	}{
		{"fold_kelvin", `{"\u212a":"kelvin"}`},
		{"fold_longs", `{"\u017f":"longs"}`},
		{"fold_sharps_no_ss", `{"ß":"no"}`},
		{"fold_accent", `{"É":"accent"}`},
		{"fold_dotless_i_no", `{"ı":"no"}`},
	} {
		type FoldS struct {
			K  string `json:"k"`
			SS string `json:"ss"`
			E  string `json:"é"`
			S  string `json:"s"`
			I  string `json:"I"`
		}
		var s FoldS
		if err := json.Unmarshal([]byte(tc.inp), &s); err != nil {
			panic(err)
		}
		res := fmt.Sprintf("k=%s|ss=%s|e=%s|s=%s|i=%s", s.K, s.SS, s.E, s.S, s.I)
		emit("UNM_STRUCT", tc.name, hex.EncodeToString([]byte(tc.inp)), hex.EncodeToString([]byte(res)))
	}

	{
		type Exact struct {
			Upper string `json:"A"`
			Lower string `json:"a"`
		}
		var ex Exact
		inp := `{"a":"low","A":"up"}`
		_ = json.Unmarshal([]byte(inp), &ex)
		res := fmt.Sprintf("A=%s|a=%s", ex.Upper, ex.Lower)
		emit("UNM_STRUCT", "exact_vs_fold", hex.EncodeToString([]byte(inp)), hex.EncodeToString([]byte(res)))
	}

	for _, tc := range []struct {
		name string
		inp  string
	}{
		{"slice_null", `{"environments":null}`},
		{"slice_empty", `{"environments":[]}`},
		{"slice_dup_null", `{"environments":["x","y"],"environments":[null]}`},
		{"slice_dup_cap", `{"environments":["x","y"],"environments":["a"],"environments":[null,null]}`},
		{"slice_dup_short_grow", `{"environments":["x","y","z"],"environments":["a"],"environments":[null,null,null,null]}`},
		{"slice_dup_empty_null", `{"environments":["x","y"],"environments":[],"environments":[null]}`},
		{"slice_dup_nullval_then_null", `{"environments":["x","y"],"environments":null,"environments":[null]}`},
		{"slice_dup_to_null", `{"environments":["x","y"],"environments":null}`},
		{"slice_dup_to_empty", `{"environments":["x","y"],"environments":[]}`},
	} {
		type SlS struct {
			Envs []string `json:"environments"`
		}
		var s SlS
		_ = json.Unmarshal([]byte(tc.inp), &s)
		res := "NIL"
		if s.Envs != nil {
			res = fmt.Sprintf("LEN=%d:%s", len(s.Envs), strings.Join(s.Envs, ","))
		}
		emit("UNM_STRUCT", tc.name, hex.EncodeToString([]byte(tc.inp)), hex.EncodeToString([]byte(res)))
	}

	for _, tc := range []struct {
		name string
		inp  string
	}{
		{"struct_slice_dup_cap", `{"matrix":[{"name":"a","runner":"r1"},{"name":"b","runner":"r2"}],"matrix":[{"name":"c"}],"matrix":[null,{"runner":"r9"}]}`},
		{"struct_slice_dup_null_elem", `{"matrix":[{"name":"a","runner":"r1"},{"name":"b","runner":"r2"}],"matrix":[null]}`},
		{"struct_slice_dup_empty", `{"matrix":[{"name":"a","runner":"r1"}],"matrix":[],"matrix":[null]}`},
		{"struct_slice_dup_nullval", `{"matrix":[{"name":"a","runner":"r1"}],"matrix":null,"matrix":[null]}`},
		{"struct_slice_dup_to_null", `{"matrix":[{"name":"a","runner":"r1"}],"matrix":null}`},
	} {
		type Entry struct {
			Name   string `json:"name"`
			Runner string `json:"runner"`
		}
		type PlanS struct {
			Matrix []Entry `json:"matrix"`
		}
		var p PlanS
		_ = json.Unmarshal([]byte(tc.inp), &p)
		res := "NIL"
		if p.Matrix != nil {
			parts := make([]string, len(p.Matrix))
			for i, e := range p.Matrix {
				parts[i] = fmt.Sprintf("%s/%s", e.Name, e.Runner)
			}
			res = fmt.Sprintf("LEN=%d:%s", len(p.Matrix), strings.Join(parts, ","))
		}
		emit("UNM_STRUCT", tc.name, hex.EncodeToString([]byte(tc.inp)), hex.EncodeToString([]byte(res)))
	}

	{
		type Inner struct {
			Name string `json:"name"`
		}
		type Outer struct {
			In     Inner   `json:"in"`
			Matrix []Inner `json:"matrix"`
		}
		var o1 Outer
		inp1 := `{"in":{"name":123}}`
		e1 := json.Unmarshal([]byte(inp1), &o1)
		emit("UNM_STRUCT", "nest_struct", hex.EncodeToString([]byte(inp1)), hex.EncodeToString([]byte("ERR:"+e1.Error())))

		var o2 Outer
		inp2 := `{"matrix":[{"name":123}]}`
		e2 := json.Unmarshal([]byte(inp2), &o2)
		emit("UNM_STRUCT", "nest_slice", hex.EncodeToString([]byte(inp2)), hex.EncodeToString([]byte("ERR:"+e2.Error())))
	}

	for _, tc := range []struct {
		name string
		inp  string
	}{
		{"map_slice_dup", `{"m":{"k":["x","y"]},"m":{"k":[null]}}`},
		{"map_slice_dup_inner", `{"m":{"k":["x","y"],"k":["a"],"k":[null,null]}}`},
		{"map_slice_dup_merge_keys", `{"m":{"a":["x"]},"m":{"b":["y"]}}`},
		{"map_slice_dup_null", `{"m":{"a":["x"]},"m":null}`},
		{"map_slice_dup_empty_obj", `{"m":{"a":["x"]},"m":{}}`},
	} {
		type C struct {
			M map[string][]string `json:"m"`
		}
		var c C
		_ = json.Unmarshal([]byte(tc.inp), &c)
		res := "NIL"
		if c.M != nil {
			ks := make([]string, 0, len(c.M))
			for k := range c.M {
				ks = append(ks, k)
			}
			sort.Strings(ks)
			parts := make([]string, len(ks))
			for i, k := range ks {
				parts[i] = fmt.Sprintf("%s=LEN=%d:%s", k, len(c.M[k]), strings.Join(c.M[k], ","))
			}
			res = strings.Join(parts, "|")
		}
		emit("UNM_STRUCT", tc.name, hex.EncodeToString([]byte(tc.inp)), hex.EncodeToString([]byte(res)))
	}

	for _, tc := range []struct {
		name string
		inp  string
	}{
		{"map_str_null", `{"m":null}`},
		{"map_str_empty", `{"m":{}}`},
		{"map_str_merge", `{"m":{"a":"1"},"m":{"b":"2"}}`},
		{"map_str_overwrite", `{"m":{"a":"1"},"m":{"a":"2"}}`},
		{"map_str_null_val_overwrites", `{"m":{"a":"1"},"m":{"a":null}}`},
		{"map_str_dup_null_resets", `{"m":{"a":"1"},"m":null}`},
		{"map_str_dup_null_then_obj", `{"m":{"a":"1"},"m":null,"m":{"b":"2"}}`},
		{"map_str_dup_empty_keeps", `{"m":{"a":"1"},"m":{}}`},
		{"map_str_err_not_obj", `{"m":123}`},
		{"map_str_err_val_type", `{"m":{"a":1}}`},
	} {
		type SM struct {
			M map[string]string `json:"m"`
		}
		var sm SM
		err := json.Unmarshal([]byte(tc.inp), &sm)
		res := "NIL"
		if err != nil {
			res = "ERR:" + err.Error()
		} else if sm.M != nil {
			ks := make([]string, 0, len(sm.M))
			for k := range sm.M {
				ks = append(ks, k)
			}
			sort.Strings(ks)
			parts := make([]string, len(ks))
			for i, k := range ks {
				parts[i] = fmt.Sprintf("%s=%s", k, sm.M[k])
			}
			res = "MAP:" + strings.Join(parts, "|")
		}
		emit("UNM_STRUCT", tc.name, hex.EncodeToString([]byte(tc.inp)), hex.EncodeToString([]byte(res)))
	}
}
