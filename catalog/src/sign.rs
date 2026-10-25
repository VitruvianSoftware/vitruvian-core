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

//! sign.py: signs catalog/tools.json and writes the two files the website
//! serves.

use crate::argparse::{Kind, Opt, Parser};
use crate::pyerr::{self, Crash, Res};
use crate::{here, pypath, pystr, signing};

const DESCRIPTION: &str = "Signs catalog/tools.json and writes the two files the website serves.";

fn opt(s: &'static str, dest: &'static str, required: bool) -> Opt {
    Opt {
        strings: vec![s],
        dest,
        kind: Kind::Value,
        help: None,
        required,
    }
}

fn parser() -> Parser {
    Parser {
        prog: "sign.py".into(),
        description: Some(DESCRIPTION.into()),
        opts: vec![
            Opt::help(),
            opt("--catalog", "catalog", false),
            opt("--public-key", "public_key", false),
            opt("--key-env", "key_env", false),
            opt("--out", "out", true),
        ],
    }
}

/// `main(argv)`: the exit status, having printed what sign.py prints.
pub fn main(argv: &[String]) -> i32 {
    let values = match parser().parse(argv, &|_, _| Ok(())) {
        Ok(v) => v,
        Err(exit) => {
            print!("{}", exit.stdout);
            eprint!("{}", exit.stderr);
            return exit.code;
        }
    };
    let here = here::catalog_dir().to_string_lossy().into_owned();
    let catalog = values
        .value("catalog")
        .map(pypath::norm)
        .unwrap_or_else(|| pypath::join(&here, "tools.json"));
    let public_key = values
        .value("public_key")
        .map(pypath::norm)
        .unwrap_or_else(|| pypath::join(&here, "public-key.txt"));
    let key_env = values
        .value("key_env")
        .unwrap_or("CATALOG_SIGNING_KEY")
        .to_string();
    let out_arg = pypath::norm(values.value("out").unwrap_or(""));
    match run(&catalog, &public_key, &key_env, &out_arg) {
        Ok(code) => code,
        Err(c) => pyerr::finish(&c),
    }
}

fn run(catalog: &str, public_key: &str, key_env: &str, out_arg: &str) -> Res<i32> {
    let workspace = std::env::var("BUILD_WORKSPACE_DIRECTORY").unwrap_or_default();
    let out = if pypath::is_absolute(out_arg) || workspace.is_empty() {
        out_arg.to_string()
    } else {
        pypath::join(&workspace, out_arg)
    };
    let private = std::env::var_os(key_env)
        .map(|v| v.to_string_lossy().into_owned())
        .unwrap_or_default();
    if private.is_empty() {
        eprintln!("sign: {} is empty: nothing was signed", key_env);
        return Ok(2);
    }
    let wanted = pystr::strip(&pyerr::read_text_ascii(public_key)?).to_string();
    let have = match signing::public_key_of(&private) {
        Ok(h) => h,
        Err(problem) => {
            eprintln!("sign: {}: nothing was signed", problem);
            return Ok(2);
        }
    };
    if have != wanted {
        eprintln!(
            "sign: the key in {} is not the one whose public half is in {} ({} is not {}): nothing was signed",
            key_env,
            pypath::name(public_key),
            have,
            wanted
        );
        return Ok(2);
    }
    let data = pyerr::read_bytes(catalog)?;
    let signature = signing::sign(&data, &private).map_err(|m| Crash::new("ValueError", m))?;
    if !signing::verify(&data, &signature, &wanted) {
        eprintln!("sign: the signature does not verify: nothing was signed");
        return Ok(2);
    }
    make_dirs(&out)?;
    let tools = pypath::join(&out, "tools.json");
    pyerr::write_bytes(&tools, &data)?;
    pyerr::write_bytes(&pypath::join(&out, "tools.json.sig"), &signature)?;
    println!(
        "sign: wrote {} ({} bytes) and its signature",
        tools,
        data.len()
    );
    Ok(0)
}

/// `path.mkdir(parents=True, exist_ok=True)`.
pub fn make_dirs(path: &str) -> Res<()> {
    let p = std::path::Path::new(path);
    if p.is_dir() {
        return Ok(());
    }
    std::fs::create_dir_all(p).map_err(|e| Crash::os(&e, path))
}
