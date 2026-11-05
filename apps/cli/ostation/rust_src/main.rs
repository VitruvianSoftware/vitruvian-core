// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! `ostation`: local client for the Olight Ostation 2 Pro charger.

use ostation_lib::client::{fetch_status, DEFAULT_PORT};
use ostation_lib::relay::{self, RelayConfig};
use ostation_lib::{parse_key, Error, Result};

const USAGE: &str = "\
ostation: local client for the Olight Ostation 2 Pro

USAGE:
    ostation status [--host HOST] [--port PORT] [--key LOCALKEY]
    ostation relay  [--listen ADDR] [--host HOST] [--port PORT] [--adb-serial SERIAL]

OPTIONS (environment fallbacks in brackets):
    --host        charger address            [OSTATION_HOST, default 192.168.86.70]
    --port        charger port               [OSTATION_PORT, default 6668]
    --key         16-byte Tuya localKey      [OSTATION_LOCAL_KEY, required for status]
    --listen      relay listen address       [default 127.0.0.1:1999]
    --adb-serial  adb device for the relay   [OSTATION_ADB_SERIAL, default: the only device]

The charger serves one LAN session at a time: stop the Olight app first.";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => {}
        Err(e) => {
            eprintln!("ostation: {e}");
            std::process::exit(if matches!(e, Error::Usage(_)) { 2 } else { 1 });
        }
    }
}

/// `--name value` pairs after the subcommand.
fn flags(args: &[String]) -> Result<Vec<(&str, &str)>> {
    let mut out = Vec::new();
    let mut it = args.iter();
    while let Some(name) = it.next() {
        let value = it
            .next()
            .ok_or_else(|| Error::Usage(format!("{name} needs a value\n\n{USAGE}")))?;
        out.push((name.as_str(), value.as_str()));
    }
    Ok(out)
}

fn pick(flags: &[(&str, &str)], name: &str, env: &str) -> Option<String> {
    flags
        .iter()
        .find(|(n, _)| *n == name)
        .map(|(_, v)| v.to_string())
        .or_else(|| std::env::var(env).ok())
}

fn run(args: &[String]) -> Result<()> {
    let Some((cmd, rest)) = args.split_first() else {
        return Err(Error::Usage(USAGE.into()));
    };
    if matches!(cmd.as_str(), "-h" | "--help" | "help") {
        println!("{USAGE}");
        return Ok(());
    }
    let f = flags(rest)?;
    for (name, _) in &f {
        if !["--host", "--port", "--key", "--listen", "--adb-serial"].contains(name) {
            return Err(Error::Usage(format!("unknown option {name}\n\n{USAGE}")));
        }
    }
    let host = pick(&f, "--host", "OSTATION_HOST").unwrap_or_else(|| "192.168.86.70".into());
    let port = match pick(&f, "--port", "OSTATION_PORT") {
        Some(p) => p
            .parse()
            .map_err(|_| Error::Usage(format!("bad port {p}")))?,
        None => DEFAULT_PORT,
    };
    match cmd.as_str() {
        "status" => {
            let key = pick(&f, "--key", "OSTATION_LOCAL_KEY")
                .ok_or_else(|| Error::Usage("set --key or OSTATION_LOCAL_KEY".into()))?;
            let status = fetch_status(&host, port, &parse_key(&key)?)?;
            println!(
                "{}",
                serde_json::to_string_pretty(&status).expect("JSON value")
            );
            Ok(())
        }
        "relay" => relay::run(&RelayConfig {
            listen: pick(&f, "--listen", "OSTATION_LISTEN")
                .unwrap_or_else(|| "127.0.0.1:1999".into()),
            target_host: host,
            target_port: port,
            adb_serial: pick(&f, "--adb-serial", "OSTATION_ADB_SERIAL"),
        }),
        other => Err(Error::Usage(format!("unknown command {other}\n\n{USAGE}"))),
    }
}
