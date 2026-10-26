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

use std::env;
use std::process;
use std::thread;
use std::time::Duration;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let daemon_args = match mac_stats_daemon::parse_daemon_args(&args) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("Error: {}", e);
            process::exit(1);
        }
    };

    if daemon_args.help {
        println!("{}", mac_stats_daemon::usage());
        return;
    }

    if daemon_args.once {
        let stats = mac_stats_daemon::collect_all_stats(true, &daemon_args.repo);
        let packet = format!("{}\n", stats);

        match daemon_args.mode.as_str() {
            "serial" => {
                let port = daemon_args
                    .port
                    .or_else(mac_stats_daemon::find_esp32_serial_port);
                match port {
                    Some(p) => {
                        if let Err(e) =
                            mac_stats_daemon::send_over_serial(&p, daemon_args.baud, &packet)
                        {
                            eprintln!("Error: {}", e);
                            process::exit(1);
                        }
                    }
                    None => {
                        print!("{}", packet);
                    }
                }
            }
            "http" => {
                if let Err(e) = mac_stats_daemon::send_over_http(
                    &daemon_args.host,
                    daemon_args.udp_port,
                    &packet,
                ) {
                    eprintln!("Error: {}", e);
                    process::exit(1);
                }
            }
            _ => {
                print!("{}", packet);
            }
        }
        return;
    }

    eprintln!(
        "ESP32-S3 Mac Desktop Companion Daemon starting (mode={}, interval={}s)...",
        daemon_args.mode, daemon_args.interval
    );

    loop {
        let stats = mac_stats_daemon::collect_all_stats(true, &daemon_args.repo);
        let packet = format!("{}\n", stats);

        match daemon_args.mode.as_str() {
            "serial" => {
                let port = daemon_args
                    .port
                    .clone()
                    .or_else(mac_stats_daemon::find_esp32_serial_port);
                if let Some(ref p) = port {
                    if let Err(e) = mac_stats_daemon::send_over_serial(p, daemon_args.baud, &packet)
                    {
                        eprintln!("Serial error: {}", e);
                    }
                }
            }
            "http" => {
                if let Err(e) = mac_stats_daemon::send_over_http(
                    &daemon_args.host,
                    daemon_args.udp_port,
                    &packet,
                ) {
                    eprintln!("UDP error: {}", e);
                }
            }
            _ => {
                print!("{}", packet);
            }
        }

        thread::sleep(Duration::from_secs_f64(daemon_args.interval));
    }
}
