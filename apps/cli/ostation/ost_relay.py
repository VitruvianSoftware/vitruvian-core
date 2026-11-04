# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Persistent relay: 127.0.0.1:1999 -> adb -> phone nc -> 192.168.86.70:6668"""

import socket, subprocess, threading

srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 1999))
srv.listen(1)
print("relay listening on 1999", flush=True)

while True:
    cli, _ = srv.accept()
    print("client connected", flush=True)
    adb = subprocess.Popen(
        [
            "adb",
            "-s",
            "100.64.0.1:41091",
            "shell",
            "-T",
            "toybox",
            "nc",
            "192.168.86.70",
            "6668",
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )

    def pump(src, dst):
        try:
            while True:
                b = src.read(4096)
                if not b:
                    break
                dst.write(b)
                dst.flush()
        except Exception:
            pass
        finally:
            try:
                adb.kill()
            except Exception:
                pass

    t1 = threading.Thread(
        target=pump, args=(cli.makefile("rb"), adb.stdin), daemon=True
    )
    t2 = threading.Thread(
        target=pump, args=(adb.stdout, cli.makefile("wb")), daemon=True
    )
    t1.start()
    t2.start()
    t1.join()
    cli.close()
    print("session ended", flush=True)
