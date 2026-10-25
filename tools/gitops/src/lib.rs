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

//! fedora_power_cycle.py in Rust, standard library only: the same command
//! line, the same bytes to the Kasa HS300 strip, the same output and exit
//! codes. Where the script dies with an uncaught exception, the port prints
//! a traceback header and the same last line (`ConnectionRefusedError:
//! [Errno 61] Connection refused`, `KeyError: 'id'`, ...) and exits 1. The
//! parity test (fedora_power_cycle_rs_parity_test.py) holds the two together
//! against a fake strip on localhost.

pub mod argparse;
pub mod json;
pub mod pystr;

use std::io::{self, Read, Write};
use std::net::{IpAddr, Ipv4Addr, SocketAddr, TcpStream, ToSocketAddrs};
use std::time::Duration;

use argparse::{Kind, Opt, Parser};
use json::Value;

pub const HS300_DEFAULT_IP: &str = "192.168.86.48";
pub const HS300_DEFAULT_PORT: i64 = 9999;
pub const OUTLET_ALIAS_MATCH: &str = "NUC12I9";
pub const OUTLET_DEFAULT_CHILD_ID: &str = "8006E93B6F541837D78FE0E0D9E0DAD62338476A05";
/// `s.settimeout(5.0)`: for the connect and for every send and recv.
const TIMEOUT: Duration = Duration::from_secs(5);
/// The longest `time.sleep` takes: _PyTime_t is nanoseconds in an i64.
const MAX_SLEEP_SECONDS: i64 = i64::MAX / 1_000_000_000;

/// An exception the script does not catch: its class and message.
#[derive(Debug, Clone, PartialEq)]
pub struct Crash {
    pub class: String,
    pub msg: String,
}

impl Crash {
    pub fn new(class: &str, msg: impl Into<String>) -> Crash {
        Crash {
            class: class.into(),
            msg: msg.into(),
        }
    }

    /// The traceback Python prints. Only the last line can match, since the
    /// port has no Python frames to show.
    pub fn traceback(&self) -> String {
        format!(
            "Traceback (most recent call last):\n  File \"<rust port>\", line 0, in <module>\n{}: {}\n",
            self.class, self.msg
        )
    }

    fn no_attribute(v: &Value, attr: &str) -> Crash {
        Crash::new(
            "AttributeError",
            format!("'{}' object has no attribute '{}'", v.type_name(), attr),
        )
    }
}

/// An OSError from a socket call, named and worded the way Python does.
fn os_crash(e: &io::Error) -> Crash {
    use io::ErrorKind as K;
    // A socket timeout (settimeout) is TimeoutError("timed out"): Rust's
    // connect_timeout says TimedOut with no errno, and a read or write past
    // its timeout fails with EAGAIN.
    if e.kind() == K::WouldBlock || (e.kind() == K::TimedOut && e.raw_os_error().is_none()) {
        return Crash::new("TimeoutError", "timed out");
    }
    let class = match e.kind() {
        K::ConnectionRefused => "ConnectionRefusedError",
        K::ConnectionReset => "ConnectionResetError",
        K::ConnectionAborted => "ConnectionAbortedError",
        K::BrokenPipe => "BrokenPipeError",
        K::TimedOut => "TimeoutError",
        K::PermissionDenied => "PermissionError",
        _ => "OSError",
    };
    let text = e.to_string();
    let text = match text.rfind(" (os error ") {
        Some(i) => text[..i].to_string(),
        None => text,
    };
    match e.raw_os_error() {
        Some(code) => Crash::new(class, format!("[Errno {}] {}", code, text)),
        None => Crash::new(class, text),
    }
}

/// socket.gaierror for a name getaddrinfo could not resolve. Rust keeps
/// gai_strerror's text but not the EAI code, so the code comes from the text.
fn gai_crash(detail: &str) -> Crash {
    let lower = detail.to_lowercase();
    let code = if cfg!(target_os = "macos") {
        if lower.contains("temporary failure") {
            2
        } else {
            8
        }
    } else if lower.contains("temporary failure") {
        -3
    } else if lower.contains("no address associated") {
        -5
    } else {
        -2
    };
    Crash::new("socket.gaierror", format!("[Errno {}] {}", code, detail))
}

fn no_name() -> Crash {
    gai_crash(if cfg!(target_os = "macos") {
        "nodename nor servname provided, or not known"
    } else {
        "Name or service not known"
    })
}

/// The IPv4 address an AF_INET socket's connect((host, port)) uses: the
/// first one getaddrinfo gives, with Python's two special names.
fn resolve(host: &str) -> Result<Ipv4Addr, Crash> {
    match host {
        "" => return Ok(Ipv4Addr::UNSPECIFIED),
        "<broadcast>" => return Ok(Ipv4Addr::BROADCAST),
        _ => {}
    }
    if host.contains('\0') {
        return Err(Crash::new("ValueError", "embedded null character"));
    }
    let addrs = (host, 0).to_socket_addrs().map_err(|e| {
        let text = e.to_string();
        match text.strip_prefix("failed to lookup address information: ") {
            Some(detail) => gai_crash(detail),
            None => no_name(),
        }
    })?;
    for a in addrs {
        if let IpAddr::V4(v4) = a.ip() {
            return Ok(v4);
        }
    }
    Err(no_name())
}

/// The strip's framing: a 4-byte big-endian length (of the string, in
/// characters, as `len(string)` counts), then each UTF-8 byte XORed with the
/// previous ciphertext byte, starting from 171.
pub fn encrypt(string: &str) -> Vec<u8> {
    let mut key: u8 = 171;
    let mut result = (string.chars().count() as u32).to_be_bytes().to_vec();
    for b in string.bytes() {
        let a = key ^ b;
        key = a;
        result.push(a);
    }
    result
}

/// The reverse, decoding with errors="replace".
pub fn decrypt(data: &[u8]) -> String {
    let mut key: u8 = 171;
    let mut out = Vec::with_capacity(data.len());
    for &b in data {
        out.push(key ^ b);
        key = b;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// `send_kasa_command(ip, cmd, port)`: one connection, one command, one
/// JSON answer.
pub fn send_kasa_command(ip: &str, cmd: &Value, port: i64) -> Result<Value, Crash> {
    let cmd_str = json::dumps(cmd);
    let addr = resolve(ip)?;
    if !(0..=65535).contains(&port) {
        return Err(Crash::new(
            "OverflowError",
            "connect(): port must be 0-65535.",
        ));
    }
    let mut s =
        TcpStream::connect_timeout(&SocketAddr::new(IpAddr::V4(addr), port as u16), TIMEOUT)
            .map_err(|e| os_crash(&e))?;
    s.set_read_timeout(Some(TIMEOUT))
        .map_err(|e| os_crash(&e))?;
    s.set_write_timeout(Some(TIMEOUT))
        .map_err(|e| os_crash(&e))?;
    s.write_all(&encrypt(&cmd_str)).map_err(|e| os_crash(&e))?;
    // One recv(4), as the script does: fewer bytes is a truncated header.
    let mut header = [0u8; 4];
    let n = recv(&mut s, &mut header)?;
    if n < 4 {
        return Err(Crash::new(
            "RuntimeError",
            "Truncated response header from Kasa strip",
        ));
    }
    let total_len = u32::from_be_bytes(header) as usize;
    let mut payload = Vec::new();
    let mut buf = vec![0u8; 4096];
    while payload.len() < total_len {
        let want = 4096.min(total_len - payload.len());
        let n = recv(&mut s, &mut buf[..want])?;
        if n == 0 {
            break;
        }
        payload.extend_from_slice(&buf[..n]);
    }
    json::loads(&decrypt(&payload))
        .map_err(|e| Crash::new("json.decoder.JSONDecodeError", e.to_string()))
}

fn recv(s: &mut TcpStream, buf: &mut [u8]) -> Result<usize, Crash> {
    loop {
        match s.read(buf) {
            Ok(n) => return Ok(n),
            // Python retries a recv interrupted by a signal (PEP 475).
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(os_crash(&e)),
        }
    }
}

// --------------------------------------------------------------------------
// The script's dict and str operations, with the errors Python raises.
// --------------------------------------------------------------------------

/// `v.get(key, default)`.
fn get(v: &Value, key: &str, default: Value) -> Result<Value, Crash> {
    match v {
        Value::Obj(_) => Ok(v.get(key).cloned().unwrap_or(default)),
        _ => Err(Crash::no_attribute(v, "get")),
    }
}

/// `for item in v`.
fn iterate(v: &Value) -> Result<Vec<Value>, Crash> {
    match v {
        Value::Arr(items) => Ok(items.clone()),
        Value::Obj(items) => Ok(json::dedup(items)
            .into_iter()
            .map(|(k, _)| Value::Str(k))
            .collect()),
        Value::Str(s) => Ok(s.chars().map(|c| Value::Str(c.to_string())).collect()),
        _ => Err(Crash::new(
            "TypeError",
            format!("'{}' object is not iterable", v.type_name()),
        )),
    }
}

/// `OUTLET_ALIAS_MATCH.lower() in alias.lower()`.
fn alias_matches(alias: &Value) -> Result<bool, Crash> {
    match alias {
        Value::Str(s) => Ok(s
            .to_lowercase()
            .contains(&OUTLET_ALIAS_MATCH.to_lowercase())),
        _ => Err(Crash::no_attribute(alias, "lower")),
    }
}

fn sysinfo_children(ip: &str, port: i64) -> Result<Vec<Value>, Crash> {
    let sysinfo = send_kasa_command(ip, &get_sysinfo_command(), port)?;
    let system = get(&sysinfo, "system", Value::Obj(vec![]))?;
    let info = get(&system, "get_sysinfo", Value::Obj(vec![]))?;
    iterate(&get(&info, "children", Value::Arr(vec![]))?)
}

fn obj(items: Vec<(&str, Value)>) -> Value {
    Value::Obj(items.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
}

/// `{"system": {"get_sysinfo": {}}}`
pub fn get_sysinfo_command() -> Value {
    obj(vec![("system", obj(vec![("get_sysinfo", obj(vec![]))]))])
}

/// `{"context": {"child_ids": [child_id]}, "system": {"set_relay_state": {"state": state}}}`
pub fn set_relay_state_command(child_id: &Value, state: i64) -> Value {
    obj(vec![
        (
            "context",
            obj(vec![("child_ids", Value::Arr(vec![child_id.clone()]))]),
        ),
        (
            "system",
            obj(vec![(
                "set_relay_state",
                obj(vec![("state", Value::Int(state.to_string()))]),
            )]),
        ),
    ])
}

/// `find_child_id(ip, port)`: the id of the first outlet whose alias names
/// the NUC, else the id it was last seen with.
pub fn find_child_id(ip: &str, port: i64) -> Result<Value, Crash> {
    for child in sysinfo_children(ip, port)? {
        if alias_matches(&get(&child, "alias", Value::Str(String::new()))?)? {
            return child
                .get("id")
                .cloned()
                .ok_or_else(|| Crash::new("KeyError", "'id'"));
        }
    }
    Ok(Value::Str(OUTLET_DEFAULT_CHILD_ID.into()))
}

/// `get_relay_state(ip, child_id, port)`: the outlet's `state`, whatever
/// type the strip sent, or 0.
pub fn get_relay_state(ip: &str, child_id: &Value, port: i64) -> Result<Value, Crash> {
    for child in sysinfo_children(ip, port)? {
        let id = get(&child, "id", Value::Null)?;
        if id.py_eq(child_id) || alias_matches(&get(&child, "alias", Value::Str(String::new()))?)? {
            return get(&child, "state", Value::Int("0".into()));
        }
    }
    Ok(Value::Int("0".into()))
}

pub fn set_relay_state(ip: &str, child_id: &Value, state: i64, port: i64) -> Result<Value, Crash> {
    send_kasa_command(ip, &set_relay_state_command(child_id, state), port)
}

// --------------------------------------------------------------------------
// Command line.
// --------------------------------------------------------------------------

fn opt(strings: Vec<&'static str>, dest: &'static str, kind: Kind, help: &str) -> Opt {
    Opt {
        strings,
        dest,
        kind,
        help: Some(help.into()),
        required: false,
    }
}

fn parser(prog: String) -> Parser {
    Parser {
        prog,
        description: Some("Power-cycle host fedora via Kasa HS300 power strip.".into()),
        opts: vec![
            Opt::help(),
            opt(
                vec!["--ip", "--host"],
                "ip",
                Kind::Value,
                "IP of Kasa HS300 power strip",
            ),
            opt(
                vec!["--port"],
                "port",
                Kind::Value,
                &format!("TCP port of the strip (default: {})", HS300_DEFAULT_PORT),
            ),
            opt(
                vec!["--status"],
                "status",
                Kind::Flag,
                "Print current outlet power state",
            ),
            opt(
                vec!["--cycle"],
                "cycle",
                Kind::Flag,
                "Power-cycle outlet (OFF, wait, ON)",
            ),
            opt(vec!["--off"], "off", Kind::Flag, "Turn outlet OFF"),
            opt(vec!["--on"], "on", Kind::Flag, "Turn outlet ON"),
            opt(
                vec!["--wait"],
                "wait",
                Kind::Value,
                "Seconds to wait between OFF and ON (default: 8)",
            ),
        ],
    }
}

fn prog_name(argv0: &str) -> String {
    match argv0.rfind('/') {
        Some(i) => argv0[i + 1..].to_string(),
        None => argv0.to_string(),
    }
}

fn say(line: &str) {
    let mut out = io::stdout();
    let _ = writeln!(out, "{}", line);
}

/// What the script does once its arguments are read.
/// `str(int(text))` for a value argparse already accepted: canonical
/// digits, whatever their size (i64 saturates; Python's int does not).
fn int_text(text: &str) -> String {
    let t = pystr::strip(text);
    let (neg, body) = match t.chars().next() {
        Some('-') => (true, &t[1..]),
        Some('+') => (false, &t[1..]),
        _ => (false, t),
    };
    let digits: String = body
        .chars()
        .filter_map(pystr::decimal_value)
        .map(|d| char::from_digit(d, 10).unwrap())
        .collect();
    let digits = digits.trim_start_matches('0');
    match (neg, digits.is_empty()) {
        (_, true) => "0".into(),
        (true, false) => format!("-{}", digits),
        (false, false) => digits.into(),
    }
}

#[allow(clippy::too_many_arguments)]
fn act(
    ip: &str,
    port: i64,
    wait: i64,
    wait_text: &str,
    status: bool,
    off: bool,
    on: bool,
) -> Result<(), Crash> {
    let child_id = find_child_id(ip, port)?;
    let shown = child_id.py_str();
    if status {
        let state = get_relay_state(ip, &child_id, port)?;
        let word = if state.py_eq(&Value::Int("1".into())) {
            "ON"
        } else {
            "OFF"
        };
        say(&format!(
            "Outlet '{}' ({}): {}",
            OUTLET_ALIAS_MATCH, shown, word
        ));
        return Ok(());
    }
    if off || on {
        let (word, state) = if off { ("OFF", 0) } else { ("ON", 1) };
        say(&format!(
            "Turning {} outlet '{}' ({})...",
            word, OUTLET_ALIAS_MATCH, shown
        ));
        set_relay_state(ip, &child_id, state, port)?;
        say("Done.");
        return Ok(());
    }
    // Power-cycle when --cycle, or no action at all, is given.
    say(&format!(
        "Power-cycling host 'fedora' via outlet '{}' ({})...",
        OUTLET_ALIAS_MATCH, ip
    ));
    say("Cutting power (relay state -> 0)...");
    set_relay_state(ip, &child_id, 0, port)?;
    say(&format!("Waiting {} seconds...", wait_text));
    if wait < 0 {
        return Err(Crash::new(
            "ValueError",
            "sleep length must be non-negative",
        ));
    }
    if wait > MAX_SLEEP_SECONDS {
        return Err(Crash::new(
            "OverflowError",
            "timestamp too large to convert to C _PyTime_t",
        ));
    }
    let _ = io::stdout().flush();
    std::thread::sleep(Duration::from_secs(wait as u64));
    say("Restoring power (relay state -> 1)...");
    set_relay_state(ip, &child_id, 1, port)?;
    say("Power-cycle complete. Host 'fedora' will reboot and rejoin the cluster automatically.");
    Ok(())
}

/// `main()`: the exit code, having printed what the script prints.
pub fn run(argv: &[String]) -> i32 {
    let prog = prog_name(
        argv.first()
            .map(String::as_str)
            .unwrap_or("fedora_power_cycle.py"),
    );
    let p = parser(prog);
    let convert = |dest: &str, value: &str| -> Result<(), &'static str> {
        match dest {
            "port" | "wait" => argparse::py_int(value).map(|_| ()).ok_or("int"),
            _ => Ok(()),
        }
    };
    let values = match p.parse(&argv[1.min(argv.len())..], &convert) {
        Ok(v) => v,
        Err(exit) => {
            print!("{}", exit.stdout);
            eprint!("{}", exit.stderr);
            return exit.code;
        }
    };
    let int = |dest: &str, default: i64| {
        values
            .value(dest)
            .and_then(argparse::py_int)
            .unwrap_or(default)
    };
    let wait_text = values.value("wait").map_or("8".to_string(), int_text);
    let ip = values.value("ip").unwrap_or(HS300_DEFAULT_IP).to_string();
    let result = act(
        &ip,
        int("port", HS300_DEFAULT_PORT),
        int("wait", 8),
        &wait_text,
        values.flag("status"),
        values.flag("off"),
        values.flag("on"),
    );
    match result {
        Ok(()) => 0,
        Err(c) => {
            let _ = io::stdout().flush();
            eprint!("{}", c.traceback());
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::thread;

    #[test]
    fn encrypts_as_the_script_does() {
        // fedora_power_cycle.encrypt('{"system": {"get_sysinfo": {}}}').hex()
        let want = "0000001fd0f281f88bff9af7d5efcfb496f194e0bfccb5c6afc1a7c8ead0f08bf68bf6";
        let got: String = encrypt(&json::dumps(&get_sysinfo_command()))
            .iter()
            .map(|b| format!("{:02x}", b))
            .collect();
        assert_eq!(got, want);
        assert_eq!(encrypt(""), vec![0, 0, 0, 0]);
    }

    #[test]
    fn decrypt_undoes_encrypt_and_replaces_bad_utf8() {
        for text in ["", "{}", "{\"alias\": \"NUC12I9 \\u00e9\"}", "plain ascii"] {
            assert_eq!(decrypt(&encrypt(text)[4..]), text);
        }
        // 0xff XOR 171 = 0x54 'T'; an invalid byte becomes U+FFFD.
        let mut cipher = Vec::new();
        let mut key = 171u8;
        for b in [b'a', 0xff, b'b'] {
            let c = key ^ b;
            cipher.push(c);
            key = c;
        }
        assert_eq!(decrypt(&cipher), "a\u{fffd}b");
    }

    #[test]
    fn commands_are_json_dumps_bytes() {
        assert_eq!(
            json::dumps(&set_relay_state_command(&Value::Str("ABC".into()), 1)),
            r#"{"context": {"child_ids": ["ABC"]}, "system": {"set_relay_state": {"state": 1}}}"#
        );
        assert_eq!(
            json::dumps(&set_relay_state_command(&Value::Str("é".into()), 0)),
            r#"{"context": {"child_ids": ["\u00e9"]}, "system": {"set_relay_state": {"state": 0}}}"#
        );
    }

    /// A one-connection strip that answers `reply` (already framed).
    fn strip(reply: Vec<u8>) -> (u16, thread::JoinHandle<String>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let handle = thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut head = [0u8; 4];
            s.read_exact(&mut head).unwrap();
            let mut body = vec![0u8; u32::from_be_bytes(head) as usize];
            s.read_exact(&mut body).unwrap();
            s.write_all(&reply).unwrap();
            decrypt(&body)
        });
        (port, handle)
    }

    #[test]
    fn finds_the_outlet_by_alias_case_insensitively() {
        let reply = encrypt(
            r#"{"system": {"get_sysinfo": {"children": [{"id": "A", "alias": "tv"}, {"id": "B", "alias": "my nuc12i9"}]}}}"#,
        );
        let (port, h) = strip(reply);
        assert_eq!(
            find_child_id("127.0.0.1", port as i64).unwrap(),
            Value::Str("B".into())
        );
        assert_eq!(h.join().unwrap(), r#"{"system": {"get_sysinfo": {}}}"#);
    }

    #[test]
    fn crashes_read_as_python_words_them() {
        let (port, _h) = strip(vec![0, 0]);
        assert_eq!(
            send_kasa_command("127.0.0.1", &get_sysinfo_command(), port as i64).unwrap_err(),
            Crash::new("RuntimeError", "Truncated response header from Kasa strip")
        );
        let (port, _h) = strip(encrypt("[1]"));
        assert_eq!(
            find_child_id("127.0.0.1", port as i64).unwrap_err(),
            Crash::new("AttributeError", "'list' object has no attribute 'get'")
        );
        let (port, _h) = strip(encrypt(
            r#"{"system": {"get_sysinfo": {"children": [{"alias": "NUC12I9"}]}}}"#,
        ));
        assert_eq!(
            find_child_id("127.0.0.1", port as i64).unwrap_err(),
            Crash::new("KeyError", "'id'")
        );
        let (port, _h) = strip(encrypt("nope"));
        assert_eq!(
            find_child_id("127.0.0.1", port as i64).unwrap_err().class,
            "json.decoder.JSONDecodeError"
        );
        assert_eq!(
            send_kasa_command("127.0.0.1", &get_sysinfo_command(), 70000).unwrap_err(),
            Crash::new("OverflowError", "connect(): port must be 0-65535.")
        );
        // Nothing listens on a port just freed.
        let freed = TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let c = send_kasa_command("127.0.0.1", &get_sysinfo_command(), freed as i64).unwrap_err();
        assert_eq!(c.class, "ConnectionRefusedError");
        assert!(c.msg.starts_with("[Errno "), "{}", c.msg);
    }

    #[test]
    fn iteration_and_attributes_follow_python() {
        assert_eq!(
            iterate(&Value::Int("1".into())).unwrap_err().msg,
            "'int' object is not iterable"
        );
        assert_eq!(iterate(&Value::Str("ab".into())).unwrap().len(), 2);
        assert_eq!(
            alias_matches(&Value::Null).unwrap_err().msg,
            "'NoneType' object has no attribute 'lower'"
        );
        assert!(alias_matches(&Value::Str("xNuC12i9y".into())).unwrap());
    }

    #[test]
    fn int_text_is_str_of_int() {
        assert_eq!(int_text(" +0_08 "), "8");
        assert_eq!(int_text("-0"), "0");
        assert_eq!(int_text("\u{0663}"), "3");
        assert_eq!(
            int_text("99999999999999999999999"),
            "99999999999999999999999"
        );
    }
}
