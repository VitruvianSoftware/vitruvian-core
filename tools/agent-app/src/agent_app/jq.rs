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

//! The four jq programs agent-app.sh runs locally on GitHub's answers,
//! implemented as thin filters over `vitruvian_jq` (matching jq 1.8.2):
//! `.token` and `.pem` (with `-re`), convert's summary line, the
//! installations table, and the repository list (with `-r`).

use vitruvian_jq::{each, interpolate, one, run as jq_run, Produced, RunOptions, RunResult, Value};

/// The jq programs agent-app.sh runs.
pub enum Prog<'a> {
    /// `.KEY`
    Field(&'a str),
    /// `"app_id=\(.id)\nslug=\(.slug)\nowner=\(.owner.login)\nkey=" + $out`
    Convert(&'a str),
    /// `.[] | "installation_id=\(.id)\taccount=\(.account.login)\tselection=\(.repository_selection)"`
    Installations,
    /// `.repositories[].full_name`
    Repos,
}

fn eval(prog: &Prog, v: &Value) -> Produced {
    match prog {
        Prog::Field(k) => one(v.index(k)),
        // jq evaluates a string's interpolations right-to-left, so when two
        // would fail, the error is the later one's.
        Prog::Convert(out) => one((|| -> Result<Value, String> {
            let login = interpolate(&v.index("owner")?.index("login")?);
            let slug = interpolate(&v.index("slug")?);
            let id = interpolate(&v.index("id")?);
            Ok(Value::String(format!(
                "app_id={id}\nslug={slug}\nowner={login}\nkey={out}"
            )))
        })()),
        Prog::Installations => each(v.iterate(), |x| {
            one((|| -> Result<Value, String> {
                let sel = interpolate(&x.index("repository_selection")?);
                let acct = interpolate(&x.index("account")?.index("login")?);
                let id = interpolate(&x.index("id")?);
                Ok(Value::String(format!(
                    "installation_id={id}\taccount={acct}\tselection={sel}"
                )))
            })())
        }),
        Prog::Repos => each(v.index("repositories").and_then(|r| r.iterate()), |x| {
            one(x.index("full_name"))
        }),
    }
}

pub fn run(prog: &Prog, input: &[u8], exit_status: bool) -> RunResult {
    let opts = if exit_status {
        RunOptions::raw_exit()
    } else {
        RunOptions::raw()
    };
    jq_run(input, opts, |v| eval(prog, v))
}
