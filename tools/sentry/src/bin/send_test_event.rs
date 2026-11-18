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

//! CLI entrypoint for `//tools/sentry:send-test-event`.

use sentry_tools::http::{AuthHeader, CurlClient};
use sentry_tools::send_test_event::{
    execute, format_rfc3339_utc, generate_event_id, parse_args, ENVELOPE_CONTENT_TYPE,
    SENTRY_CLIENT, SENTRY_USER_AGENT, USAGE,
};
use std::process::ExitCode;
use std::time::SystemTime;

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let args = match parse_args(&argv) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("send-test-event: {e}\n\n{USAGE}");
            return ExitCode::from(2);
        }
    };
    if args.help {
        print!("{USAGE}");
        return ExitCode::SUCCESS;
    }

    let dsn = args.dsn.as_ref().expect("dsn validated when !help");
    let event_id = match generate_event_id() {
        Ok(id) => id,
        Err(e) => {
            eprintln!("send-test-event: {e}");
            return ExitCode::from(1);
        }
    };
    let sent_at = match format_rfc3339_utc(SystemTime::now()) {
        Ok(ts) => ts,
        Err(e) => {
            eprintln!("send-test-event: {e}");
            return ExitCode::from(1);
        }
    };

    let curl_bin = std::env::var("SENTRY_CURL_BIN").unwrap_or_else(|_| "curl".into());
    let mut client = match CurlClient::new(
        curl_bin,
        AuthHeader::SentryAuth {
            public_key: dsn.public_key.clone(),
            client: SENTRY_CLIENT.into(),
        },
    ) {
        Ok(c) => c
            .with_content_type(ENVELOPE_CONTENT_TYPE)
            .with_header(format!("User-Agent: {SENTRY_USER_AGENT}")),
        Err(e) => {
            eprintln!("send-test-event: {e}");
            return ExitCode::from(1);
        }
    };

    let code = execute(
        &args,
        &event_id,
        &sent_at,
        &mut client,
        &mut std::io::stdout(),
        &mut std::io::stderr(),
    );
    drop(client);
    ExitCode::from(u8::try_from(code).unwrap_or(1))
}
